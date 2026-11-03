#if canImport(MobileVLCKit)
import Foundation
import UIKit
import MobileVLCKit
import LemonPlayback

/// MobileVLCKit 内核适配（ADR-003）。
/// 注意：VLCKit 回调在后台线程，统一用 `Task { @MainActor }` 送回主线程。
@MainActor
final class VLCKitEngine: NSObject, PlaybackEngine {
    private let player = VLCMediaPlayer()
    private var durationValue: TimeInterval = 0
    private var stateValue: PlaybackState = .idle
    private var audioTracksValue: [PlaybackTrack] = []
    private var subtitleTracksValue: [PlaybackTrack] = []
    private var externalSubtitleURLs: [URL] = []

    override init() {
        super.init()
        player.delegate = self
    }

    // MARK: - 渲染视图绑定（VLCKit 用 drawable）

    func attachRenderSurface(_ view: UIView) {
        player.drawable = view
    }

    // MARK: - PlaybackEngine

    var state: PlaybackState { stateValue }

    var currentTime: TimeInterval {
        guard let time = player.time, time.intValue > 0 else { return 0 }
        return TimeInterval(time.intValue) / 1000.0
    }

    var duration: TimeInterval {
        if let length = player.media?.length, length.intValue > 0 {
            return TimeInterval(length.intValue) / 1000.0
        }
        return durationValue
    }

    var rate: Float {
        get { player.rate }
        set { player.rate = newValue }
    }

    var audioTracks: [PlaybackTrack] { audioTracksValue }
    var subtitleTracks: [PlaybackTrack] { subtitleTracksValue }

    func load(_ source: PlaybackSource) async throws {
        stateValue = .preparing
        durationValue = 0
        audioTracksValue = []
        subtitleTracksValue = []
        externalSubtitleURLs = []

        guard let media = VLCMedia(url: source.url) else {
            stateValue = .failed(PlaybackError.engine("无法创建播放媒体").localizedDescription)
            throw PlaybackError.engine("无法创建播放媒体")
        }
        media.addOption(":network-caching=1500")
        media.addOption(":http-referrer=\(source.headers["Referer"] ?? "https://www.guangyupan.com/")")
        if let userAgent = source.headers["User-Agent"] {
            media.addOption(":http-user-agent=\(userAgent)")
        }
        player.media = media
        player.play()
    }

    func play() {
        guard stateValue.isActive else { return }
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.stop()
        stateValue = .ended
    }

    func seek(to time: TimeInterval) async {
        let milliseconds = Int32(clamping: Int(time * 1000))
        player.time = VLCTime(int: milliseconds)
        refreshTracks()
    }

    func selectAudioTrack(id: Int32) {
        player.currentAudioTrackIndex = id
    }

    func selectSubtitleTrack(id: Int32?) {
        player.currentVideoSubTitleIndex = id ?? -1
    }

    func addExternalSubtitle(url: URL, encoding: String.Encoding?) async throws {
        player.addPlaybackSlave(url, type: .subtitle, enforce: false)
        externalSubtitleURLs.append(url)
        refreshTracks()
    }

    func removeExternalSubtitles() {
        externalSubtitleURLs = []
        player.currentVideoSubTitleIndex = -1
        refreshTracks()
    }

    // MARK: - 轨道

    private func refreshTracks() {
        audioTracksValue = player.audioTrackIndexes.compactMap { number in
            let index = (number as? NSNumber)?.int32Value ?? Int32(truncating: number as? NSNumber ?? 0)
            return PlaybackTrack(id: index, name: "音轨 \(index)", language: nil, kind: .audio)
        }
        subtitleTracksValue = player.videoSubTitlesIndexes.compactMap { number in
            let index = (number as? NSNumber)?.int32Value ?? Int32(truncating: number as? NSNumber ?? 0)
            let name = index < 0 ? "关闭字幕" : "字幕 \(index)"
            return PlaybackTrack(id: index, name: name, language: nil, kind: .subtitle)
        }
        + externalSubtitleURLs.enumerated().map { offset, url in
            PlaybackTrack(id: Int32(offset), name: url.lastPathComponent, language: nil, kind: .subtitle, isExternal: true)
        }
    }
}

extension VLCKitEngine: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshTracks()
            switch self.player.state {
            case .playing:
                self.stateValue = .playing
            case .paused:
                self.stateValue = .paused
            case .buffering:
                self.stateValue = .buffering(progress: 0)
            case .opening:
                self.stateValue = .preparing
            case .ended:
                self.stateValue = .ended
            case .error:
                self.stateValue = .failed("VLC 播放错误")
            default:
                break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.durationValue == 0, let length = self.player.media?.length, length.intValue > 0 {
                self.durationValue = TimeInterval(length.intValue) / 1000.0
            }
        }
    }
}
#endif
