import Foundation
import MediaPlayer
import AVFoundation

/// 锁屏 / 控制中心（Now Playing）与远程控制。
@MainActor
final class NowPlayingController {
    static let shared = NowPlayingController()

    private var configured = false
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?

    func configure() {
        guard !configured else { return }
        configured = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.onPause?()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isCurrentlyPlaying {
                self.onPause?()
            } else {
                self.onPlay?()
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.onSeek?(event.positionTime)
            return .success
        }
    }

    func update(title: String, duration: TimeInterval, position: TimeInterval, rate: Float, isPlaying: Bool) {
        isCurrentlyPlaying = isPlaying
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        isCurrentlyPlaying = false
    }

    private(set) var isCurrentlyPlaying = false
}
