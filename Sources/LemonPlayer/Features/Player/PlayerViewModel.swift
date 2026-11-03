import Foundation
import Observation
import AVFAudio
import LemonGuangya
import LemonNetwork
import LemonPlayback
import LemonSubtitle

/// 播放页状态：取直链 → 加载内核 → 自动匹配外挂字幕 → 进度轮询 → 控制。
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
    @ObservationIgnored private var subtitleFiles: [GuangyaFile] = []
    var rate: Float = 1

    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let service: GuangyaFileService
    @ObservationIgnored private let http = HTTPClient()
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    init(file: GuangyaFile, session: SessionStore) {
        self.file = file
        self.session = session
        self.service = GuangyaFileService(identity: session.identity)
        self.engine = PlaybackEngineFactory.make()
    }

    func start() async {
        phase = .loading
        configureAudioSession()
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
            await autoAttachSubtitle()
        } catch {
            phase = .failed(message(for: error))
        }
    }

    func retry() async {
        await start()
    }

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
        }
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        engine.rate = newRate
    }

    func stop() {
        progressTask?.cancel()
        progressTask = nil
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 外挂字幕

    /// 同目录同名自动匹配：列出父目录 → 过滤字幕 → 规范化匹配 → 取最高分加载。
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

    /// 用户手动选择某个候选字幕。
    func attachCandidate(_ candidate: SubtitleCandidate) async {
        guard let matched = subtitleFiles.first(where: { $0.name == candidate.fileName }) else {
            subtitleNotice = "字幕文件不在当前目录"
            return
        }
        await attach(matched)
    }

    /// 下载字幕 → 自动识别编码并转 UTF-8 → 交给内核。
    /// 不直接把签名直链交给 VLC：一是直链可能要求 Referer/UA，二是 GBK 需要转码。
    func attach(_ subtitleFile: GuangyaFile) async {
        do {
            let token = try await session.validAccessToken()
            let link = try await service.playbackURL(fileID: subtitleFile.id, accessToken: token)

            let response = try await http.send(
                HTTPRequest(url: link.url, headers: link.headers)
            )
            guard response.isSuccess else {
                subtitleNotice = "字幕下载失败"
                return
            }

            let decoded = SubtitleTextDecoder.decode(response.data)
            let tempURL = try writeTemporarySubtitle(
                text: decoded.text,
                fileName: subtitleFile.name
            )
            try await engine.addExternalSubtitle(url: tempURL, encoding: .utf8)
            attachedSubtitleName = subtitleFile.name
            subtitleNotice = nil
        } catch {
            subtitleNotice = "字幕加载失败：\(error.localizedDescription)"
        }
    }

    func disableSubtitles() {
        engine.selectSubtitleTrack(id: nil)
        attachedSubtitleName = nil
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

    // MARK: - 音频会话（后台播放）

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            // 不阻塞播放
        }
    }

    // MARK: - 进度

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
