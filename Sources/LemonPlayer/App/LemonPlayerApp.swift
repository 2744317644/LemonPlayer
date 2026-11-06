import SwiftUI

@main
@MainActor
struct LemonPlayerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SessionStore()

    init() {
        _ = AppMetrics.launchStartedAt
        // 海报/字幕等网络资源统一走 URLCache，减少重复下载（AsyncImage 使用共享缓存）
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}
