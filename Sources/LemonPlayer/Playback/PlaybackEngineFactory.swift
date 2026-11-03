import Foundation
import LemonPlayback

/// 播放引擎工厂：有 MobileVLCKit（CocoaPods 注入）时用真实内核，否则降级为 Mock
/// （保证在没有 Pods 的环境下工程仍可编译，例如纯 SPM 试验或本地无网构建）。
@MainActor
enum PlaybackEngineFactory {
    static func make() -> PlaybackEngine {
        #if canImport(MobileVLCKit)
        return VLCKitEngine()
        #else
        return MockPlaybackEngine()
        #endif
    }

    static var isRealEngineAvailable: Bool {
        #if canImport(MobileVLCKit)
        return true
        #else
        return false
        #endif
    }
}
