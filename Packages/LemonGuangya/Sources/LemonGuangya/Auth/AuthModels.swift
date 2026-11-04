import Foundation

/// `POST /v1/auth/device/code` 的响应。
/// 字段名已对照真实响应核对（2026-11-03）：
/// `device_code` / `user_code` / `expires_in` / `interval` / `verification_url` / `verification_uri_complete`。
public struct DeviceCode: Codable, Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let expiresIn: Int
    public let interval: Int
    public let verificationURL: String?
    public let verificationURIComplete: String?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case expiresIn = "expires_in"
        case interval
        case verificationURL = "verification_url"
        case verificationURIComplete = "verification_uri_complete"
    }

    public init(
        deviceCode: String,
        userCode: String,
        expiresIn: Int,
        interval: Int,
        verificationURL: String?,
        verificationURIComplete: String?
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.expiresIn = expiresIn
        self.interval = interval
        self.verificationURL = verificationURL
        self.verificationURIComplete = verificationURIComplete
    }

    /// 用于生成二维码的内容：优先带 user_code 的完整授权页。
    public var qrContent: String {
        verificationURIComplete ?? verificationURL ?? ""
    }
}

/// 登录成功后的 token 三元组（账户域响应为扁平 OAuth2 风格）。
public struct TokenBundle: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int
    public let tokenType: String?
    public let subject: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case subject = "sub"
    }

    public init(
        accessToken: String,
        refreshToken: String,
        expiresIn: Int,
        tokenType: String? = nil,
        subject: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.tokenType = tokenType
        self.subject = subject
    }

    /// 宽容解析：登录接口（signin / device token）不同版本可能把 token 放在顶层或 `data` 里。
    public static func decodeLenient(from data: Data) throws -> TokenBundle {
        if let bundle = try? JSONDecoder().decode(TokenBundle.self, from: data),
           !bundle.accessToken.isEmpty {
            return bundle
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GuangyaError.api(code: -1, message: "登录响应无法解析")
        }

        func find(_ key: String, in dictionary: [String: Any], depth: Int = 0) -> Any? {
            if let value = dictionary[key] { return value }
            guard depth < 3 else { return nil }
            for (_, value) in dictionary {
                if let nested = value as? [String: Any],
                   let found = find(key, in: nested, depth: depth + 1) {
                    return found
                }
            }
            return nil
        }

        guard let access = (find("access_token", in: object) ?? find("accessToken", in: object)) as? String,
              !access.isEmpty else {
            throw GuangyaError.api(code: -1, message: "登录响应缺少 access_token")
        }
        let refresh = (find("refresh_token", in: object) ?? find("refreshToken", in: object)) as? String ?? ""
        let expires = (find("expires_in", in: object) ?? find("expiresIn", in: object)) as? Int ?? 3600
        let subject = (find("sub", in: object) ?? find("subject", in: object)) as? String
        return TokenBundle(accessToken: access, refreshToken: refresh, expiresIn: expires, subject: subject)
    }
}

/// 当前用户（`GET /v1/user/me`）。仅 `sub` 字段可靠，其余字段未验证，不建模。
public struct UserMe: Decodable, Sendable, Equatable {
    public let subject: String

    enum CodingKeys: String, CodingKey {
        case subject = "sub"
    }

    public init(subject: String) {
        self.subject = subject
    }
}
