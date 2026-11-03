import Foundation
import Observation
import AVFAudio
import LemonGuangya
import LemonNetwork
import LemonPersistence
import LemonPlayback
import LemonSubtitle

/// 播放页状态：取直链 → 加载内核 → 恢复进度 → 自动匹配字幕 → 进度轮询/上报 → 控制。
@MainActor
@Observable
final class PlayerViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let file: GuangyaFile
    let engine: PlaybackEngine

    private(set) var phase: Phase = .loading
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var subtitleCandidates: [SubtitleCandidate] = []
    private(set) var attachedSubtitleName: String?
    private(set) var subtitleNotice: String?
    private(set) var subtitleOffsetValue: TimeInterval = 0
    private(set) var resumeNotice: String?
    var rate: Float = 1

    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let service: GuangyaFileService
    @ObservationIgnored private let http = HTTPClient()
    @ObservationIgnored private let progressStore = PlaybackProgressStore()
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var subtitleFiles: [GuangyaFile] = []
    @ObservationIgnored private var currentSubtitleFile: GuangyaFile?
    @ObservationIgnored private var subtitleRawText: String?
    @ObservationIgnored private var subtitleFormat: SubtitleFormat = .unknown
    @ObservationIgnored private var subtitleOffset: TimeInterval = 0
    @ObservationIgnored private var recoveryAttempts = 0
    @ObservationIgnored private var isRecovering = false
    @ObservationIgnored private var tickCount = 0

    init(file: GuangyaFile, session: SessionStore) {
        self.file = file
        self.session = session
        self.service = GuangyaFileService(identity: session.identity)
        self.engine = PlaybackEngineFactory.make()
    }

    // MARK: - 生命周期

    func start() async {
        phase = .loading
        configureAudioSession()
        configureRemoteCommands()
        do {
            let token = try await session.validAccessToken()
            let link = try await service.playbackURL(fileID: file.id, accessToken: token)
            try await engine.load(
                PlaybackSource(url: link.url, headers: link.headers, title: file.name)
            )
            rate = engine.rate
            phase = .ready
            isPlaying = true
            startProgressLoop()
            await applyResumePosition()
            await autoAttachSubtitle()
        } catch {
            phase = .failed(message(for: error))
        }
    }

    func stop() {
        progressTask?.cancel()
        progressTask = nil
        saveProgress()
        engine.stop()
        NowPlayingController.shared.clear()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func retry() async {
        recoveryAttempts = 0
        await start()
    }

    // MARK: - 控制

    func togglePlay() {
        switch engine.state {
        case .playing:
            engine.pause()
            isPlaying = false
        case .paused, .ready:
            engine.play()
            isPlaying = true
        default:
            break
        }
    }

    func seek(to value: Double) {
        Task { [weak self] in
            guard let self else { return }
            await self.engine.seek(to: value)
            self.currentTime = value
            self.saveProgress()
        }
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        engine.rate = newRate
    }

    // MARK: - 断点续播

    private func applyResumePosition() async {
        guard let saved = await progressStore.progress(for: file.id) else { return }
        guard saved.position > 5 else { return }
        if saved.duration > 0, saved.position > saved.duration - 15 {
            return // 已接近结尾，不恢复
        }
        await engine.seek(to: saved.position)
        currentTime = saved.position
        resumeNotice = "已跳转到上次位置 \(Self.format(saved.position))"
    }

    private func saveProgress() {
        guard phase == .ready, currentTime > 0 else { return }
        let snapshot = PlaybackProgress(fileID: file.id, position: currentTime, duration: duration)
        Task { [progressStore] in
            await progressStore.save(snapshot)
        }
    }

    // MARK: - 错误恢复（直链过期 / 网络中断）

    private func recoverPlayback() async {
        guard !isRecovering, recoveryAttempts < 2 else { return }
        isRecovering = true
        recoveryAttempts += 1
        let position = currentTime
        do {
            let token = try await session.refreshAccessToken()
            let link = try await service.playbackURL(fileID: file.id, accessToken: token)
            try await engine.load(
                PlaybackSource(url: link.url, headers: link.headers, title: file.name)
            )
            await engine.seek(to: position)
            currentTime = position
            phase = .ready
            isPlaying = true
            resumeNotice = "播放地址已刷新"
        } catch {
            phase = .failed("播放恢复失败：\(message(for: error))")
        }
        isRecovering = false
    }

    // MARK: - 外挂字幕

    func autoAttachSubtitle() async {
        guard file.isPlayable else { return }
        do {
            let token = try await session.validAccessToken()
            let page = try await service.listFiles(
                parentID: file.parentID,
                page: 0,
                pageSize: 200,
                orderBy: 3,
                sortType: 0,
                accessToken: token
            )
            let subtitleFiles = page.items.filter { SubtitleMatcher.isSubtitleFile($0.name) }
            self.subtitleFiles = subtitleFiles
            let candidates = SubtitleMatcher.candidates(
                videoName: file.name,
                subtitleNames: subtitleFiles.map(\.name)
            )
            subtitleCandidates = candidates
            if let best = candidates.first,
               let matched = subtitleFiles.first(where: { $0.name == best.fileName }) {
                await attach(matched)
            }
        } catch {
            subtitleNotice = "字幕匹配失败（不影响播放）"
        }
    }

    func attachCandidate(_ candidate: SubtitleCandidate) async {
        guard let matched = subtitleFiles.first(where: { $0.name == candidate.fileName }) else {
            subtitleNotice = "字幕文件不在当前目录"
            return
        }
        await attach(matched)
    }

    /// 下载字幕 → 识别编码并转 UTF-8 → 缓存原文 → 按当前偏移注入内核。
    func attach(_ subtitleFile: GuangyaFile) async {
        do {
            let token = try await session.validAccessToken()
            let link = try await service.playbackURL(fileID: subtitleFile.id, accessToken: token)
            let response = try await http.send(HTTPRequest(url: link.url, headers: link.headers))
            guard response.isSuccess else {
                subtitleNotice = "字幕下载失败"
                return
            }

            let decoded = SubtitleTextDecoder.decode(response.data)
            currentSubtitleFile = subtitleFile
            subtitleRawText = decoded.text
            subtitleFormat = SubtitleParser.detectFormat(
                fileExtension: subtitleFile.ext,
                text: decoded.text
            )
            subtitleOffset = 0
            subtitleOffsetValue = 0
            await applySubtitleContent()
        } catch {
            subtitleNotice = "字幕加载失败：\(error.localizedDescription)"
        }
    }

    func adjustSubtitleOffset(_ delta: TimeInterval) async {
        subtitleOffset = ((subtitleOffset + delta) * 10).rounded() / 10
        subtitleOffsetValue = subtitleOffset
        await applySubtitleContent()
    }

    func resetSubtitleOffset() async {
        subtitleOffset = 0
        subtitleOffsetValue = 0
        await applySubtitleContent()
    }

    func disableSubtitles() {
        engine.selectSubtitleTrack(id: nil)
        attachedSubtitleName = nil
    }

    private func applySubtitleContent() async {
        guard let subtitleFile = currentSubtitleFile, let rawText = subtitleRawText else { return }
        do {
            let transformed: String
            if subtitleFormat == .ass {
                transformed = ASSSubtitleShifter.shift(rawText, after: subtitleOffset)
            } else {
                let cues = SubtitleParser.parseCues(text: rawText, format: subtitleFormat)
                transformed = SubtitleSerializer.srt(from: cues, offset: subtitleOffset)
            }
            let tempURL = try writeTemporarySubtitle(text: transformed, fileName: subtitleFile.name)
            try await engine.addExternalSubtitle(url: tempURL, encoding: .utf8)
            attachedSubtitleName = subtitleFile.name
            subtitleNotice = nil
        } catch {
            subtitleNotice = "字幕加载失败：\(error.localizedDescription)"
        }
    }

    private func writeTemporarySubtitle(text: String, fileName: String) throws -> URL {
        let ext = fileName.split(separator: ".").last.map(String.init) ?? "srt"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemonPlayerSubtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - 音频会话 / 远程控制

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            // 不阻塞播放
        }
    }

    private func configureRemoteCommands() {
        let controller = NowPlayingController.shared
        controller.onPlay = { [weak self] in self?.togglePlay() }
        controller.onPause = { [weak self] in
            guard let self, self.engine.state == .playing else { return }
            self.togglePlay()
        }
        controller.onSeek = { [weak self] time in self?.seek(to: time) }
        controller.configure()
    }

    // MARK: - 进度轮询

    var formattedPosition: String { Self.format(currentTime) }
    var formattedDuration: String { Self.format(duration) }

    private func startProgressLoop() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.currentTime = self.engine.currentTime
                if self.duration == 0 {
                    self.duration = self.engine.duration
                }
                self.isPlaying = (self.engine.state == .playing)

                NowPlayingController.shared.update(
                    title: self.file.name,
                    duration: self.duration,
                    position: self.currentTime,
                    rate: self.rate,
                    isPlaying: self.isPlaying
                )

                // 每 5 秒落盘一次进度
                self.tickCount += 1
                if self.tickCount % 10 == 0 {
                    self.saveProgress()
                }

                // 直链过期/断网：自动重取一次
                if case .failed = self.engine.state, !self.isRecovering {
                    await self.recoverPlayback()
                }
            }
        }
    }

    private func message(for error: Error) -> String {
        if let error = error as? GuangyaError { return error.localizedDescription }
        if let error = error as? PlaybackError { return error.localizedDescription }
        return error.localizedDescription
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
