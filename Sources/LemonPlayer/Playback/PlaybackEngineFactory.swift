import Foundation
import LemonPlayback

/// 播放引擎工厂（双内核）：
/// - MP4/MOV/M4V → AVPlayer（原生画中画 + AirPlay）
/// - 其他（MKV/HEVC/TS…）→ MobileVLCKit（libass/全格式）
/// 没有 MobileVLCKit 时降级为 Mock，保证无 Pods 环境仍可编译。
@MainActor
enum PlaybackEngineFactory {
    private static let avPlayerExtensions: Set<String> = ["mp4", "mov", "m4v", "m4a", "mp3"]

    static func make(for fileName: String) -> PlaybackEngine {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if avPlayerExtensions.contains(ext) {
            return AVPlayerEngine()
        }
        #if canImport(MobileVLCKit)
        return VLCKitEngine(fontsDirectory: SubtitleFontStore.directory)
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
