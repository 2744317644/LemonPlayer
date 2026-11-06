import Foundation
import LemonCore

/// 请求重试策略（M2）：只对「可恢复」的错误重试，避免把写操作重放。
public struct HTTPRetryPolicy: Sendable, Equatable {
    /// 总尝试次数（含首次）。
    public var maxAttempts: Int
    /// 首次重试等待；之后按 2 倍指数退避。
    public var baseDelay: TimeInterval
    /// 单次等待上限。
    public var maxDelay: TimeInterval
    /// 这些状态码值得重试。
    public var retryableStatusCodes: Set<Int>

    public init(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 0.5,
        maxDelay: TimeInterval = 4,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = max(0, baseDelay)
        self.maxDelay = max(self.baseDelay, maxDelay)
        self.retryableStatusCodes = retryableStatusCodes
    }

    public static let `default` = HTTPRetryPolicy()
    /// 不重试（支付/写操作/一次性接口用）。
    public static let none = HTTPRetryPolicy(maxAttempts: 1)

    public func shouldRetry(statusCode: Int, attempt: Int) -> Bool {
        attempt < maxAttempts && retryableStatusCodes.contains(statusCode)
    }

    public func shouldRetry(transportError: Error, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        if transportError is CancellationError { return false }
        let nsError = transportError as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return false
        }
        return true
    }

    /// 第 `attempt` 次失败后的等待时间（attempt 从 1 开始）。
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt >= 1 else { return baseDelay }
        let exponential = baseDelay * pow(2, Double(attempt - 1))
        return min(maxDelay, exponential)
    }
}

/// 一个服务（Bangumi/光鸭/...）的 HTTP 客户端配置（M2 统一入口）。
public struct HTTPClientConfiguration: Sendable, Equatable {
    public var requestTimeout: TimeInterval
    public var resourceTimeout: TimeInterval
    /// 默认 User-Agent；不在请求里显式覆盖时使用。
    public var userAgent: String?
    public var defaultHeaders: [String: String]
    public var retryPolicy: HTTPRetryPolicy

    public init(
        requestTimeout: TimeInterval = 30,
        resourceTimeout: TimeInterval = 120,
        userAgent: String? = HTTPUserAgents.lemonPlayer,
        defaultHeaders: [String: String] = [:],
        retryPolicy: HTTPRetryPolicy = .default
    ) {
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.userAgent = userAgent
        self.defaultHeaders = defaultHeaders
        self.retryPolicy = retryPolicy
    }

    public static let `default` = HTTPClientConfiguration()

    /// Bangumi 公开接口：可识别 UA + 正常重试（限流由 RateLimiter 负责）。
    public static let bangumi = HTTPClientConfiguration(
        userAgent: HTTPUserAgents.bangumi,
        retryPolicy: HTTPRetryPolicy(maxAttempts: 3, baseDelay: 0.8, maxDelay: 5)
    )
}

/// 全项目统一的 User-Agent（避免每个模块各写一份）。
public enum HTTPUserAgents {
    public static let lemonPlayer =
        "LemonPlayer/\(LemonCore.version) (https://github.com/2744317644/LemonPlayer)"
    public static let bangumi = lemonPlayer
}

/// 简单串行限流：两次请求之间至少间隔 `minimumInterval` 秒（M2）。
public actor RateLimiter {
    private let minimumInterval: TimeInterval
    private var lastRequestAt = Date.distantPast

    public init(minimumInterval: TimeInterval = 1.0) {
        self.minimumInterval = max(0, minimumInterval)
    }

    public func wait() async {
        let elapsed = Date().timeIntervalSince(lastRequestAt)
        if elapsed < minimumInterval {
            try? await Task.sleep(for: .seconds(minimumInterval - elapsed))
        }
        lastRequestAt = Date()
    }
}
