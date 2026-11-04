import UIKit
import LemonDownloads

/// 后台下载会话事件转发：系统在后台完成下载后可能唤醒 App，
/// 必须在这里接住 completionHandler，否则系统会认为 App 未处理。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 提前建立后台会话，App 冷启动后即可接收下载事件
        _ = DownloadManager.shared
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundSessionEvents.shared.store(completionHandler, for: identifier)
        // 冷启动被后台事件唤醒时，确保会话已重建并挂上 delegate
        _ = DownloadManager.shared
    }
}
