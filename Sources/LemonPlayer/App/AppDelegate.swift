import UIKit
import LemonDownloads

/// 后台下载会话事件转发：系统在后台完成下载后可能唤醒 App，
/// 必须在这里接住 completionHandler，否则系统会认为 App 未处理。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundSessionEvents.shared.store(completionHandler, for: identifier)
    }
}
