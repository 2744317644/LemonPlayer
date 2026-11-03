import Foundation
import Observation
import LemonGuangya
import LemonPlayback

/// 播放页状态：取直链 → 加载内核 → 进度轮询 → 控制。
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
    var rate: Float = 1

    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let service: GuangyaFileService
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    init(file: GuangyaFile, session: SessionStore) {
        self.file = file
        self.session = session
        self.service = GuangyaFileService(identity: session.identity)
        self.engine = PlaybackEngineFactory.make()
    }

    func start() async {
        phase = .loading
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
    }

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
