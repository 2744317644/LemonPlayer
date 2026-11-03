import Foundation
import LemonNetwork

/// 光鸭云盘账户域客户端：设备码扫码登录、token 刷新、用户信息探针。
public struct GuangyaAuthClient: Sendable {
    public static let clientID = "aMe-8VSlkrbQXpUR"
    public static let accountBaseURL = URL(string: "https://account.guangyapan.com")!

    private let http: HTTPClient
    private let identity: DeviceIdentity

    public init(http: HTTPClient = HTTPClient(), identity: DeviceIdentity = .random()) {
        self.http = http
        self.identity = identity
    }

    // MARK: - 账号域请求头（字段名来自社区实现，已逐项核对）

    private var accountHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "x-client-version": "0.0.1",
            "x-sdk-version": "9.0.2",
            "x-protocol-version": "301",
            "x-device-model": "chrome%2F147.0.0.0",
            "x-device-name": "PC-Chrome",
            "x-device-sign": identity.sign,
            "x-os-version": "Win32",
            "x-platform-version": "1",
            "x-provider-name": "NONE",
            "x-net-work-type": "NONE",
            "x-device-id": identity.deviceID,
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"
        ]
    }

    // MARK: - ① 申请设备码

    public func requestDeviceCode() async throws -> DeviceCode {
        struct Body: Encodable {
            let scope = "user"
            let clientID = GuangyaAuthClient.clientID

            enum CodingKeys: String, CodingKey {
                case scope
                case clientID = "client_id"
            }
        }

        let request = try HTTPRequest.json(
            url: Self.accountBaseURL.appendingPathComponent("v1/auth/device/code"),
            headers: accountHeaders,
            body: Body()
        )
        let response = try await http.send(request)
        guard response.isSuccess else {
            throw GuangyaError.requestFailed(
                statusCode: response.statusCode,
                message: Self.message(from: response.data)
            )
        }
        return try response.decode(DeviceCode.self)
    }

    // MARK: - ② 轮询（未扫码时服务端返回 HTTP 400）

    public func poll(deviceCode: String) async throws -> DevicePollResult {
        struct Body: Encodable {
            let grantType = "urn:ietf:params:oauth:grant-type:device_code"
            let deviceCode: String
            let clientID = GuangyaAuthClient.clientID

            enum CodingKeys: String, CodingKey {
                case grantType = "grant_type"
                case deviceCode = "device_code"
                case clientID = "client_id"
            }
        }

        let request = try HTTPRequest.json(
            url: Self.accountBaseURL.appendingPathComponent("v1/auth/token"),
            headers: accountHeaders,
            body: Body(deviceCode: deviceCode)
        )
        let response = try await http.send(request)
        return DevicePollResult.decode(data: response.data, statusCode: response.statusCode)
    }

    // MARK: - ③ 刷新 token（refresh_token 可能轮换，必须回存）

    public func refresh(refreshToken: String) async throws -> TokenBundle {
        struct Body: Encodable {
            let grantType = "refresh_token"
            let refreshToken: String
            let clientID = GuangyaAuthClient.clientID

            enum CodingKeys: String, CodingKey {
                case grantType = "grant_type"
                case refreshToken = "refresh_token"
                case clientID = "client_id"
            }
        }

        var headers = accountHeaders
        headers["x-action"] = "401"
        headers["x-client-id"] = Self.clientID

        let request = try HTTPRequest.json(
            url: Self.accountBaseURL.appendingPathComponent("v1/auth/token"),
            headers: headers,
            body: Body(refreshToken: refreshToken)
        )
        let response = try await http.send(request)
        guard response.isSuccess else {
            throw GuangyaError.tokenExpired
        }
        return try response.decode(TokenBundle.self)
    }

    // MARK: - ④ 用户信息（token 有效性探针）

    public func me(accessToken: String) async throws -> UserMe {
        var headers = accountHeaders
        headers["Authorization"] = "Bearer \(accessToken)"

        let request = HTTPRequest(
            url: Self.accountBaseURL.appendingPathComponent("v1/user/me"),
            method: "GET",
            headers: headers
        )
        let response = try await http.send(request)
        guard response.isSuccess else {
            throw GuangyaError.tokenExpired
        }
        return try response.decode(UserMe.self)
    }

    private static func message(from data: Data) -> String {
        struct Envelope: Decodable {
            let error: String?
            let errorDescription: String?
            enum CodingKeys: String, CodingKey {
                case error
                case errorDescription = "error_description"
            }
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return "未知错误"
        }
        return envelope.errorDescription ?? envelope.error ?? "未知错误"
    }
}

public enum GuangyaError: Error, Equatable, Sendable {
    case requestFailed(statusCode: Int, message: String)
    case api(code: Int, message: String)
    case tokenExpired
    case unauthorized

    public var localizedDescription: String {
        switch self {
        case .requestFailed(let statusCode, let message):
            return "请求失败（HTTP \(statusCode)）：\(message)"
        case .api(let code, let message):
            return "接口错误（\(code)）：\(message)"
        case .tokenExpired:
            return "登录已过期，请重新扫码"
        case .unauthorized:
            return "未授权"
        }
    }
}
