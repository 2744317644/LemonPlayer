import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LemonCore

/// 一次 HTTP 请求的不可变描述。
public struct HTTPRequest: Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 30
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    /// 便捷构造 JSON 请求体。
    public static func json(
        url: URL,
        method: String = "POST",
        headers: [String: String] = [:],
        body: some Encodable,
        timeout: TimeInterval = 30
    ) throws -> HTTPRequest {
        var allHeaders = headers
        allHeaders["Content-Type"] = "application/json"
        return HTTPRequest(
            url: url,
            method: method,
            headers: allHeaders,
            body: try JSONEncoder().encode(body),
            timeout: timeout
        )
    }
}

/// 原始响应。**不对状态码做判断**——设备码轮询依赖把 4xx 的 body 当数据解析。
public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data
    public let headers: [String: String]

    public init(statusCode: Int, data: Data, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
    }

    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

public enum HTTPError: Error, Equatable, Sendable {
    case transport(String)
    case invalidResponse

    public var localizedDescription: String {
        switch self {
        case .transport(let message): return "网络请求失败：\(message)"
        case .invalidResponse: return "服务端响应格式异常"
        }
    }
}

/// 轻量 URLSession 封装：只负责发送与收集响应，错误映射交给上层。
public struct HTTPClient: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = HTTPClient.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        #if canImport(Darwin)
        configuration.waitsForConnectivity = false
        #endif
        return URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let startedAt = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            let message = "\(request.method) \(request.url.host ?? "")\(request.url.path) failed: \(error.localizedDescription)"
            Task { await DiagnosticsCenter.shared.log(.error, "network", message) }
            throw HTTPError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }

        let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
        let logMessage = "\(request.method) \(request.url.host ?? "")\(request.url.path) -> \(http.statusCode) \(milliseconds)ms"
        let logLevel: DiagnosticLevel = http.statusCode >= 400 ? .warning : .debug
        Task { await DiagnosticsCenter.shared.log(logLevel, "network", logMessage) }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }
        return HTTPResponse(statusCode: http.statusCode, data: data, headers: headers)
    }
}
