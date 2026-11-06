import Foundation

/// 全项目统一错误类型（M1）。
///
/// 上层只认 `LemonError`，网络/解析/鉴权/文件层的错误都在边界处映射成它，
/// 保证诊断日志和 UI 提示都能带出「类别 + HTTP 状态码 + 可读原因」。
public enum LemonError: Error, Equatable, Sendable, LocalizedError {
    /// 传输层失败（断网、超时、TLS）。
    case transport(String)
    /// 服务端返回了非 2xx（可能是业务错误、限流、服务端故障）。
    case http(statusCode: Int, message: String?)
    /// 401/403：登录态失效或没有权限。
    case unauthorized(statusCode: Int, message: String?)
    /// JSON/响应结构解析失败。
    case decoding(String)
    /// 文件不存在/已被删除。
    case fileNotFound(fileID: String?)
    /// 用户/任务取消。
    case cancelled
    /// 其它未归类错误。
    case unknown(String)

    public var statusCode: Int? {
        switch self {
        case .http(let code, _), .unauthorized(let code, _): return code
        default: return nil
        }
    }

    public var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    /// 是否值得重试：408/429/5xx、传输层错误。
    public var isRetryable: Bool {
        switch self {
        case .transport:
            return true
        case .http(let code, _):
            return code == 408 || code == 429 || (500..<600).contains(code)
        case .unauthorized:
            return false
        case .decoding, .fileNotFound, .cancelled, .unknown:
            return false
        }
    }

    /// 写日志/展示用的紧凑描述（不含完整响应体，避免泄露 token）。
    public var diagnosticDescription: String {
        switch self {
        case .transport(let message):
            return "transport: \(message)"
        case .http(let code, let message):
            return "http(\(code)): \(message ?? "无响应消息")"
        case .unauthorized(let code, let message):
            return "unauthorized(\(code)): \(message ?? "登录态失效")"
        case .decoding(let message):
            return "decoding: \(message)"
        case .fileNotFound(let fileID):
            return "fileNotFound: \(fileID ?? "未知文件")"
        case .cancelled:
            return "cancelled"
        case .unknown(let message):
            return "unknown: \(message)"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .transport(let message):
            return "网络连接失败：\(message)"
        case .http(let code, let message):
            return "服务返回错误（HTTP \(code)）：\(message ?? "请稍后重试")"
        case .unauthorized:
            return "登录已失效，请重新登录"
        case .decoding(let message):
            return "数据解析失败：\(message)"
        case .fileNotFound:
            return "文件不存在或已被删除"
        case .cancelled:
            return "已取消"
        case .unknown(let message):
            return "操作失败：\(message)"
        }
    }

    /// 把任意 Error 统一成 `LemonError`（已是则原样返回）。
    public static func wrap(_ error: Error) -> LemonError {
        if let lemon = error as? LemonError { return lemon }
        if error is CancellationError { return .cancelled }
        return .unknown(error.localizedDescription)
    }
}

extension DiagnosticsCenter {
    /// 记录一条错误，并附上统一后的诊断描述。
    public func log(error: LemonError, category: String = "app") async {
        await log(.error, category, error.diagnosticDescription)
    }
}
