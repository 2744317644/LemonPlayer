import UIKit
import MediaPlayer
import SwiftUI

/// 强制屏幕方向（iOS 16+）。用于全屏播放。
@MainActor
enum OrientationManager {
    /// AppDelegate 通过它回答 `supportedInterfaceOrientationsFor`：
    /// 播放页锁 landscape 时，即使系统开了「竖屏锁定」也会以横屏呈现。
    private(set) static var currentMask: UIInterfaceOrientationMask = .portrait

    static func lock(to mask: UIInterfaceOrientationMask?) {
        currentMask = mask ?? .all
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: currentMask))
        // 让 root VC 重新询问 supportedInterfaceOrientations
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

/// 系统音量控制（iOS 没有公开的 setVolume，安全做法是操作 MPVolumeView 内部的 UISlider）。
@MainActor
final class VolumeController {
    static let shared = VolumeController()
    private weak var volumeView: MPVolumeView?

    func register(_ view: MPVolumeView) {
        volumeView = view
    }

    var slider: UISlider? {
        volumeView?.subviews.compactMap { $0 as? UISlider }.first
    }

    var value: Float {
        slider?.value ?? 0
    }

    func set(_ value: Float) {
        slider?.value = min(max(value, 0), 1)
    }
}

/// 隐藏的 MPVolumeView，用来拿系统音量滑杆。
struct VolumeControlView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        view.alpha = 0.01
        VolumeController.shared.register(view)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// 屏幕亮度（UIScreen.brightness 是公开 API，但只影响本 App 显示）。
@MainActor
enum BrightnessController {
    static var value: Double {
        UIScreen.main.brightness
    }

    static func set(_ value: Double) {
        UIScreen.main.brightness = min(max(value, 0), 1)
    }
}
