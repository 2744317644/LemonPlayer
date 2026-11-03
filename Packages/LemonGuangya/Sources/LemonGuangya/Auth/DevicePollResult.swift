import Foundation

/// 设备码轮询的结果。
/// 注意：服务端用 **HTTP 400 + JSON error** 表示 `authorization_pending`，
/// 因此这里必须接收任意状态码的 body 再判断，不能依赖 2xx。
public enum DevicePollResult: Equatable, Sendable {
    case pending
    case authorized(TokenBundle)
    case expired
    case failed(String)

    public static func decode(data: Data, statusCode: Int) -> DevicePollResult {
        struct Envelope: Decodable {
            let error: String?
            let errorDescription: String?
            let accessToken: String?
            let refreshToken: String?
            let expiresIn: Int?
            let tokenType: String?
            let subject: String?

            enum CodingKeys: String, CodingKey {
                case error
                case errorDescription = "error_description"
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
                case tokenType = "token_type"
                case subject = "sub"
            }
        }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return .failed("无法解析登录响应（HTTP \(statusCode)）")
        }

        if let token = envelope.accessToken, !token.isEmpty {
            return .authorized(
                TokenBundle(
                    accessToken: token,
                    refreshToken: envelope.refreshToken ?? "",
                    expiresIn: envelope.expiresIn ?? 3600,
                    tokenType: envelope.tokenType,
                    subject: envelope.subject
                )
            )
        }

        switch envelope.error {
        case "authorization_pending":
            return .pending
        case "expired_token":
            return .expired
        case "access_denied":
            return .failed("授权被拒绝，请重试")
        case .some(let code):
            return .failed(envelope.errorDescription ?? code)
        case .none:
            return .failed("未知响应（HTTP \(statusCode)）")
        }
    }
}
