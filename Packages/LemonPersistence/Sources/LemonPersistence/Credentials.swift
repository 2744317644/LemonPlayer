import Foundation

/// 光鸭云盘登录凭据。`expiresAt` 用于提前刷新判断。
public struct Credentials: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var subject: String?

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        subject: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.subject = subject
    }

    /// 提前 60 秒视为过期，避免请求途中失效。
    public func isExpired(now: Date = Date()) -> Bool {
        now >= expiresAt.addingTimeInterval(-60)
    }
}
