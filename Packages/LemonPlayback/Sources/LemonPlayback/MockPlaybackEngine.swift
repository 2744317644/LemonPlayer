import Foundation

/// 用于单元测试与 SwiftUI Preview 的假引擎。
@MainActor
public final class MockPlaybackEngine: PlaybackEngine {
    public private(set) var state: PlaybackState = .idle
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public var rate: Float = 1
    public private(set) var audioTracks: [PlaybackTrack] = []
    public private(set) var subtitleTracks: [PlaybackTrack] = []
    public private(set) var loadedSource: PlaybackSource?
    public private(set) var externalSubtitleURLs: [URL] = []

    public init() {}

    public func load(_ source: PlaybackSource) async throws {
        state = .preparing
        loadedSource = source
        duration = 3600
        audioTracks = [PlaybackTrack(id: 0, name: "日语", language: "ja", kind: .audio)]
        subtitleTracks = [PlaybackTrack(id: 0, name: "内嵌字幕", language: "zh", kind: .subtitle)]
        state = .ready
    }

    public func play() {
        guard state.isActive else { return }
        state = .playing
    }

    public func pause() {
        guard state == .playing else { return }
        state = .paused
    }

    public func stop() {
        state = .ended
        currentTime = 0
    }

    public func seek(to time: TimeInterval) async {
        currentTime = min(max(0, time), duration)
    }

    public func selectAudioTrack(id: Int32) {
        guard audioTracks.contains(where: { $0.id == id }) else { return }
    }

    public func selectSubtitleTrack(id: Int32?) {
        if let id {
            guard subtitleTracks.contains(where: { $0.id == id }) else { return }
        }
    }

    public func addExternalSubtitle(url: URL, encoding: String.Encoding?) async throws {
        externalSubtitleURLs.append(url)
        let index = Int32(subtitleTracks.count)
        subtitleTracks.append(PlaybackTrack(id: index, name: url.lastPathComponent, language: nil, kind: .subtitle, isExternal: true))
    }

    public func removeExternalSubtitles() {
        exportExternalCleanup()
    }

    private func exportExternalCleanup() {
        subtitleTracks.removeAll { $0.isExternal }
        externalSubtitleURLs.removeAll()
    }
}
