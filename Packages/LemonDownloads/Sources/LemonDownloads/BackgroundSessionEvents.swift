import Foundation

/// 后台下载会话开始/结束事件（App 被系统唤醒时必须回调 completionHandler）。
public final class BackgroundSessionEvents: @unchecked Sendable {
    public static let shared = BackgroundSessionEvents()

    private var handlers: [String: () -> Void] = [:]
    private let lock = NSLock()

    public func store(_ handler: @escaping () -> Void, for identifier: String) {
        lock.lock()
        handlers[identifier] = handler
        lock.unlock()
    }

    public func finish(identifier: String) {
        lock.lock()
        let handler = handlers.removeValue(forKey: identifier)
        lock.unlock()
        handler?()
    }
}
