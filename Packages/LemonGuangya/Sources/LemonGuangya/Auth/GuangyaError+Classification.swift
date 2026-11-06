import Foundation

public extension GuangyaError {
    /// 接口返回的业务码（若有）。
    var apiCode: Int? {
        switch self {
        case .api(let code, _): return code
        default: return nil
        }
    }

    /// 对应的 HTTP 状态码（用于统一错误/日志）。
    var statusCode: Int? {
        switch self {
        case .requestFailed(let statusCode, _): return statusCode
        case .api(let code, _):
            switch code {
            case 117, 401: return 401
            case 403: return 403
            default: return nil
            }
        case .tokenExpired, .unauthorized: return 401
        }
    }

    /// 是否是「token 失效/无权限」——这种错误刷新 token 后重试一次才有意义。
    var isAuthFailure: Bool {
        switch self {
        case .tokenExpired, .unauthorized:
            return true
        case .requestFailed(let statusCode, _):
            return statusCode == 401 || statusCode == 403
        case .api(let code, _):
            // 117=无效 token；401/403=无权限；4022=账号密码错误（重试无意义）
            return code == 117 || code == 401 || code == 403
        }
    }
}
