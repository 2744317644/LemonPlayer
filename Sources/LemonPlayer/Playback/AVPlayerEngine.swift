import AVFoundation
import AVKit
import SwiftUI
import UIKit
import LemonPlayback

/// AVPlayer 内核：用于 MP4/MOV/M4V/HLS，换取原生画中画（PiP）与 AirPlay。
/// MKV/HEVC 等仍走 VLCKit（`PlaybackEngineFactory` 按扩展名分流）。
@MainActor
final class AVPlayerEngine: NSObject, PlaybackEngine {
    let player = AVPlayer()

    private(set) var state: PlaybackState = .idle
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var playerLayer: AVPlayerLayer?
    private var pipController: AVPictureInPictureController?

    override init() {
        super.init()
        startTicking()
        player.automaticallyWaitsToMinimizeStalling = true
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: - PlaybackEngine

    var supportsNativeASS: Bool { false }

    var currentTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    var duration: TimeInterval {
        guard let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite else {
            return 0
        }
        return itemDuration
    }

    var rate: Float {
        get { player.rate }
        set { player.rate = newValue }
    }

    var audioTracks: [PlaybackTrack] { [] }
    var subtitleTracks: [PlaybackTrack] { [] }

    func load(_ source: PlaybackSource) async throws {
        state = .preparing

        let options: [String: Any] = source.headers.isEmpty ? [:] : [
            "AVURLAssetHTTPHeaderFieldsKey": source.headers
        ]
        let asset = AVURLAsset(url: source.url, options: options)
        let item = AVPlayerItem(asset: asset)

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.state = .ended }
        }

        player.replaceCurrentItem(with: item)
        player.play()
        state = .playing
    }

    func play() {
        player.play()
        state = .playing
    }

    func pause() {
        player.pause()
        state = .paused
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .ended
    }

    func seek(to time: TimeInterval) async {
        let target = CMTime(seconds: max(0, time), preferredTimescale: 600)
        await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func selectAudioTrack(id: Int32) {}
    func selectSubtitleTrack(id: Int32?) {}
    func addExternalSubtitle(url: URL, encoding: String.Encoding?) async throws {}
    func removeExternalSubtitles() {}

    // MARK: - 渲染层 / PiP / AirPlay

    func attachPlayerLayer(_ layer: AVPlayerLayer) {
        playerLayer = layer
        layer.player = player
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pipController = AVPictureInPictureController(playerLayer: layer)
        }
    }

    var isPiPAvailable: Bool { pipController != nil }
    var isPiPActive: Bool { pipController?.isPictureInPictureActive ?? false }

    func togglePiP() {
        guard let pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
    }

    // MARK: - 状态轮询（避免 KVO 的并发问题）

    private func startTicking() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshState() }
        }
    }

    private func refreshState() {
        guard let item = player.currentItem else { return }
        if item.status == .failed {
            state = .failed(item.error?.localizedDescription ?? "AVPlayer 加载失败")
            return
        }
        if item.status == .readyToPlay, state == .preparing {
            state = .playing
        }
    }
}

/// AVPlayer 渲染视图（PiP 需要 AVPlayerLayer）。
struct AVPlayerSurface: UIViewRepresentable {
    let engine: AVPlayerEngine

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        engine.attachPlayerLayer(view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// AirPlay 路由按钮（仅 AVPlayer 内核可用）。
struct AirPlayRouteView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .yellow
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
