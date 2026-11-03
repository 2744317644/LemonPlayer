#if canImport(MobileVLCKit)
import SwiftUI
import UIKit
import LemonPlayback

/// 把 VLCKit 的 drawable UIView 桥接进 SwiftUI。
/// 用黑色背景，避免首帧前露白。
struct VLCVideoSurface: UIViewRepresentable {
    let engine: VLCKitEngine

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        engine.attachRenderSurface(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif
