import Testing
import Foundation
@testable import LemonPlayback

@Suite("PlaybackEngine")
@MainActor
struct PlaybackEngineTests {
    @Test("加载 → 播放 → 暂停 → 停止")
    func loadAndPlayFlow() async throws {
        let engine = MockPlaybackEngine()
        #expect(engine.state == .idle)

        try await engine.load(PlaybackSource(url: URL(string: "https://example.com/a.mkv")!, title: "A"))
        #expect(engine.state == .ready)
        #expect(engine.duration == 3600)
        #expect(engine.audioTracks.count == 1)

        engine.play()
        #expect(engine.state == .playing)

        engine.pause()
        #expect(engine.state == .paused)

        engine.stop()
        #expect(engine.state == .ended)
        #expect(engine.currentTime == 0)
    }

    @Test("seek 会夹在 0…duration")
    func seekClamped() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(PlaybackSource(url: URL(string: "https://example.com/a.mkv")!))

        await engine.seek(to: 100)
        #expect(engine.currentTime == 100)

        await engine.seek(to: -10)
        #expect(engine.currentTime == 0)

        await engine.seek(to: 99_999)
        #expect(engine.currentTime == 3600)
    }

    @Test("外挂字幕轨道生命周期")
    func externalSubtitleLifecycle() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(PlaybackSource(url: URL(string: "https://example.com/a.mkv")!))
        #expect(engine.subtitleTracks.count == 1)

        try await engine.addExternalSubtitle(url: URL(fileURLWithPath: "/tmp/a.chs.srt"), encoding: nil)
        #expect(engine.subtitleTracks.count == 2)
        #expect(engine.subtitleTracks[1].isExternal)

        engine.removeExternalSubtitles()
        #expect(engine.subtitleTracks.count == 1)
    }

    @Test("未加载时 play 无效果")
    func playRequiresActiveState() {
        let engine = MockPlaybackEngine()
        engine.play()
        #expect(engine.state == .idle)
    }
}
