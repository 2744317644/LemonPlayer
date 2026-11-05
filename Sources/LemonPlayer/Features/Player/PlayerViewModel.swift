import Foundation
import Observation
import AVFAudio
import LemonCore
import LemonDownloads
import LemonGuangya
import LemonNetwork
import LemonPersistence
import LemonPlayback
import LemonSubtitle

/// 播放页状态：取直链 → 加载内核 → 恢复进度 → 字幕（overlay/libass）→ 进度轮询/上报 → 控制。
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
    private(set) var secondarySubtitleName: String?
    private(set) var subtitleNotice: String?
    private(set) var resumeNotice: String?
    private(set) var subtitleOffsetValue: TimeInterval = 0
    var subtitleStyle: SubtitleStyle = .default
    var rate: Float = 1

    /// SRT/VTT 自绘字幕开关（ASS 走内核 libass，不经过这里）
    private(set) var isOverlaySubtitleActive = false
    private(set) var activeSubtitleLines: [String] = []
    /// 播放结束（用于剧集自动连播）
    private(set) var didFinish = false

    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let service: GuangyaFileService
    @ObservationIgnored private let http = HTTPClient()
    @ObservationIgnored private let progressStore = PlaybackProgressStore()
    @ObservationIgnored private let subtitlePreferenceStore = SubtitlePreferenceStore()
    @ObservationIgnored private let subtitleStyleStore = SubtitleStyleStore()
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    /// seek 后 1.2s 内不用引擎时间覆盖 UI（避免进度条被弹回原位置）
    @ObservationIgnored private var seekGuardUntil: Date?
    @ObservationIgnored private var subtitleFiles: [GuangyaFile] = []
    @ObservationIgnored private var primaryCues: [SubtitleCue] = []
    @ObservationIgnored private var secondaryCues: [SubtitleCue] = []
    @ObservationIgnored private var kernelSubtitleFile: GuangyaFile?
    @ObservationIgnored private var kernelSubtitleText: String?
    @ObservationIgnored private var mergedOffset: TimeInterval = 0
    @ObservationIgnored private var recoveryAttempts = 0
    @ObservationIgnored private var isRecovering = false
    @ObservationIgnored private var tickCount = 0

    init(file: GuangyaFile, session: SessionStore) {
        self.file = file
        self.session = session
        self.service = GuangyaFileService(identity: session.identity)
        self.engine = PlaybackEngineFactory.make(for: file.name)
    }

    // MARK: - 生命周期

    func start() async {
        phase = .loading
        subtitleStyle = await subtitleStyleStore.load()
        configureAudioSession()
        configureRemoteCommands()
        do {
            let source: PlaybackSource
            if let localURL = await DownloadManager.shared.localURL(for: file.id) {
                // 已下载：直接播本地文件（离线可用）
                source = PlaybackSource(url: localURL, headers: [:], title: file.name)
            } else {
                let token = try await session.validAccessToken()
                let link = try await service.playbackURL(fileID: file.id, accessToken: token)
                source = PlaybackSource(url: link.url, headers: link.headers, title: file.name)
            }
            try await engine.load(source)
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
        // 以本地 isPlaying 为准：VLCKit 在缓冲/seek 时状态会短暂变化，
        // 不能依赖 engine.state == .playing 判断当前是否在播放。
        if isPlaying {
            engine.pause()
            isPlaying = false
        } else {
            engine.play()
            isPlaying = true
        }
    }

    /// App 退到后台：暂停并落盘进度（如需后台音频可后续加开关）。
    func pauseForBackground() {
        guard isPlaying else { return }
        engine.pause()
        isPlaying = false
        saveProgress()
    }

    func seek(to value: Double) {
        seekGuardUntil = Date().addingTimeInterval(1.2)
        // 先更新 UI，再让引擎跳转（进度条点击/拖动立即反馈）
        currentTime = value
        refreshOverlayLines()
        Task { [weak self] in
            guard let self else { return }
            await self.engine.seek(to: value)
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
        if saved.duration > 0, saved.position > saved.duration - 15 { return }
        await engine.seek(to: saved.position)
        currentTime = saved.position
        resumeNotice = "已跳转到上次位置 \(Self.format(saved.position))"
        scheduleNoticeClear()
    }

    /// 提示 4 秒后自动消失（避免每次点屏幕都看到「已跳转到上次位置」）。
    private func scheduleNoticeClear() {
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.resumeNotice = nil
        }
    }

    private func saveProgress() {
        guard phase == .ready, currentTime > 0 else { return }
        let snapshot = PlaybackProgress(
            fileID: file.id,
            position: currentTime,
            duration: duration,
            fileName: file.name,
            parentID: file.parentID
        )
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

    // MARK: - 字幕字体

    /// 导入 ASS 自定义字体（写入字体库，VLCKit 下次 load 生效）。
    func importSubtitleFonts(_ urls: [URL]) {
        var imported = 0
        for url in urls {
            if SubtitleFontStore.importFont(from: url) != nil {
                imported += 1
            }
        }
        if imported > 0 {
            subtitleNotice = "已导入 \(imported) 个字体，重新播放后生效"
        } else {
            subtitleNotice = "字体导入失败（请选择 ttf/otf 文件）"
        }
    }

    // MARK: - 画中画 / AirPlay（仅 AVPlayer 内核）

    var isAVPlayerEngine: Bool { engine is AVPlayerEngine }

    var isPiPAvailable: Bool { (engine as? AVPlayerEngine)?.isPiPAvailable ?? false }

    func togglePiP() {
        (engine as? AVPlayerEngine)?.togglePiP()
    }

    // MARK: - 字幕

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

            // 优先恢复该文件记住的字幕选择与偏移
            if let preference = await subtitlePreferenceStore.preference(for: file.id) {
                mergedOffset = preference.offset
                subtitleOffsetValue = preference.offset
                if let name = preference.primaryFileName,
                   let matched = subtitleFiles.first(where: { $0.name == name }) {
                    await attach(matched, asSecondary: false)
                    if let secondaryName = preference.secondaryFileName,
                       let secondaryMatched = subtitleFiles.first(where: { $0.name == secondaryName }) {
                        await attach(secondaryMatched, asSecondary: true)
                    }
                    return
                }
            }

            if let best = candidates.first,
               let matched = subtitleFiles.first(where: { $0.name == best.fileName }) {
                await attach(matched, asSecondary: false)
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
        await attach(matched, asSecondary: false)
    }

    func attachSecondary(_ candidate: SubtitleCandidate) async {
        guard let matched = subtitleFiles.first(where: { $0.name == candidate.fileName }) else {
            subtitleNotice = "字幕文件不在当前目录"
            return
        }
        await attach(matched, asSecondary: true)
    }

    /// 下载字幕 → 识别编码 → SRT/VTT 走自绘 overlay，ASS 走内核 libass。
    func attach(_ subtitleFile: GuangyaFile, asSecondary: Bool) async {
        do {
            let token = try await session.validAccessToken()
            let link = try await service.playbackURL(fileID: subtitleFile.id, accessToken: token)

            // CDN 对 Accept/Referer 敏感：先按 */* + Range 请求，失败再退普通 GET
            var headers = link.headers
            headers["Accept"] = "*/*"
            headers["Range"] = "bytes=0-"
            var response = try await http.send(HTTPRequest(url: link.url, headers: headers))
            if !response.isSuccess {
                headers.removeValue(forKey: "Range")
                response = try await http.send(HTTPRequest(url: link.url, headers: headers))
            }
            guard response.isSuccess else {
                let status = response.statusCode
                subtitleNotice = "字幕下载失败（HTTP \(status)）"
                Task {
                    await DiagnosticsCenter.shared.log(
                        .error,
                        "subtitle",
                        "\(subtitleFile.name) 下载失败 HTTP \(status) host=\(link.url.host ?? "?")"
                    )
                }
                return
            }

            let decoded = SubtitleTextDecoder.decode(response.data)
            let format = SubtitleParser.detectFormat(fileExtension: subtitleFile.ext, text: decoded.text)

            if !asSecondary, format == .ass, engine.supportsNativeASS {
                // ASS：内核 libass 渲染（完整特效）
                kernelSubtitleFile = subtitleFile
                kernelSubtitleText = decoded.text
                isOverlaySubtitleActive = false
                primaryCues = []
                secondaryCues = []
                subtitleNotice = nil
                await applyKernelSubtitle()
            } else {
                // SRT/VTT（或作为副字幕的 ASS）：自绘 overlay，样式可控
                let cues = SubtitleParser.parseCues(text: decoded.text, format: format)
                if asSecondary {
                    secondaryCues = cues
                    secondarySubtitleName = subtitleFile.name
                } else {
                    primaryCues = cues
                    attachedSubtitleName = subtitleFile.name
                    isOverlaySubtitleActive = true
                    kernelSubtitleFile = nil
                    kernelSubtitleText = nil
                    engine.selectSubtitleTrack(id: nil)
                }
                refreshOverlayLines()
                subtitleNotice = nil
            }
            await persistPreference()
        } catch {
            subtitleNotice = "字幕加载失败：\(error.localizedDescription)"
        }
    }

    func adjustSubtitleOffset(_ delta: TimeInterval) async {
        mergedOffset = ((mergedOffset + delta) * 10).rounded() / 10
        subtitleOffsetValue = mergedOffset
        if isOverlaySubtitleActive {
            refreshOverlayLines()
        } else {
            await applyKernelSubtitle()
        }
        await persistPreference()
    }

    func resetSubtitleOffset() async {
        mergedOffset = 0
        subtitleOffsetValue = 0
        if isOverlaySubtitleActive {
            refreshOverlayLines()
        } else {
            await applyKernelSubtitle()
        }
        await persistPreference()
    }

    func disableSubtitles() {
        engine.selectSubtitleTrack(id: nil)
        isOverlaySubtitleActive = false
        primaryCues = []
        secondaryCues = []
        attachedSubtitleName = nil
        secondarySubtitleName = nil
        activeSubtitleLines = []
        kernelSubtitleFile = nil
        kernelSubtitleText = nil
        Task { await persistPreference() }
    }

    func updateStyle(_ style: SubtitleStyle) {
        subtitleStyle = style
        Task { [subtitleStyleStore] in
            await subtitleStyleStore.save(style)
        }
    }

    func refreshOverlayLines() {
        guard isOverlaySubtitleActive else {
            activeSubtitleLines = []
            return
        }
        let time = currentTime - mergedOffset
        var lines = SubtitleTimeline.activeTexts(in: primaryCues, at: time)
        if !secondaryCues.isEmpty {
            lines += SubtitleTimeline.activeTexts(in: secondaryCues, at: time)
        }
        activeSubtitleLines = lines
    }

    private func applyKernelSubtitle() async {
        guard let subtitleFile = kernelSubtitleFile, let rawText = kernelSubtitleText else { return }
        do {
            let shifted = ASSSubtitleShifter.shift(rawText, after: mergedOffset)
            let tempURL = try writeTemporarySubtitle(text: shifted, fileName: subtitleFile.name)
            // 先清掉旧的外部字幕，避免反复调延迟时叠加多条字幕
            engine.removeExternalSubtitles()
            try await engine.addExternalSubtitle(url: tempURL, encoding: .utf8)
            attachedSubtitleName = subtitleFile.name
            activeSubtitleLines = []
        } catch {
            subtitleNotice = "字幕加载失败：\(error.localizedDescription)"
        }
    }

    private func persistPreference() async {
        let preference = SubtitlePreference(
            primaryFileName: assignedPrimaryName,
            secondaryFileName: secondarySubtitleName,
            offset: mergedOffset
        )
        await subtitlePreferenceStore.save(preference, for: file.id)
    }

    private var assignedPrimaryName: String? {
        if isOverlaySubtitleActive { return attachedSubtitleName }
        return kernelSubtitleFile?.name
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
                try? await Task.sleep(for: .milliseconds(300))
                guard let self else { return }
                if let guardUntil = self.seekGuardUntil, Date() > guardUntil {
                    self.seekGuardUntil = nil
                }
                if self.seekGuardUntil == nil {
                    self.currentTime = self.engine.currentTime
                }
                if self.duration == 0 {
                    self.duration = self.engine.duration
                }
                switch self.engine.state {
                case .playing:
                    self.isPlaying = true
                case .paused, .ended:
                    self.isPlaying = false
                default:
                    break // 缓冲/准备中保持原状态，避免播放中错误显示“播放”图标
                }
                self.refreshOverlayLines()

                if self.engine.state == .ended {
                    self.didFinish = true
                } else if self.engine.state == .playing {
                    self.didFinish = false
                }

                NowPlayingController.shared.update(
                    title: self.file.name,
                    duration: self.duration,
                    position: self.currentTime,
                    rate: self.rate,
                    isPlaying: self.isPlaying
                )

                self.tickCount += 1
                if self.tickCount % 16 == 0 {
                    self.saveProgress()
                }

                if case .failed = self.engine.state, !self.isRecovering {
                    await self.recoverPlayback()
                }
            }
        }
    }

    private func message(for error: Error) -> String {
        let text: String
        if let error = error as? GuangyaError {
            text = error.localizedDescription
        } else if let error = error as? PlaybackError {
            text = error.localizedDescription
        } else {
            text = error.localizedDescription
        }
        Task { await DiagnosticsCenter.shared.log(.error, "player", "\(file.name): \(text)") }
        return text
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
