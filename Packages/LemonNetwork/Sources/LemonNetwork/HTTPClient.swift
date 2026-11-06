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

    /// 把非 2xx 响应映射成统一的 `LemonError`（401/403 → unauthorized）。
    public func asLemonError(message: String? = nil) -> LemonError {
        if (401...403).contains(statusCode) {
            return .unauthorized(statusCode: statusCode, message: message)
        }
        return .http(statusCode: statusCode, message: message)
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

/// 轻量 URLSession 封装：发送、重试、日志；业务错误映射交给上层。
public struct HTTPClient: @unchecked Sendable {
    public let configuration: HTTPClientConfiguration
    private let session: URLSession

    public init(
        session: URLSession = HTTPClient.makeSession(),
        configuration: HTTPClientConfiguration = .default
    ) {
        self.session = session
        self.configuration = configuration
    }

    public init(configuration: HTTPClientConfiguration) {
        self.init(
            session: HTTPClient.makeSession(configuration: configuration),
            configuration: configuration
        )
    }

    public static func makeSession(
        configuration: HTTPClientConfiguration = .default
    ) -> URLSession {
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = configuration.resourceTimeout

        var headers = configuration.defaultHeaders
        if headers["Accept"] == nil {
            headers["Accept"] = "application/json"
        }
        if let userAgent = configuration.userAgent, headers["User-Agent"] == nil {
            headers["User-Agent"] = userAgent
        }
        sessionConfiguration.httpAdditionalHeaders = headers

        #if canImport(Darwin)
        // 允许等待网络恢复：从「光鸭 App 扫码」切回来时系统可能短暂判定无网络。
        sessionConfiguration.waitsForConnectivity = true
        #endif
        return URLSession(configuration: sessionConfiguration)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await send(request, retryPolicy: configuration.retryPolicy)
    }

    /// 带重试的请求：只重试 408/429/5xx 与传输层错误。
    public func send(
        _ request: HTTPRequest,
        retryPolicy: HTTPRetryPolicy
    ) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let target = "\(request.method) \(request.url.host ?? "")\(request.url.path)"
        var attempt = 0

        while true {
            if Task.isCancelled { throw CancellationError() }
            attempt += 1
            let startedAt = Date()

            do {
                let (data, response) = try await session.data(for: urlRequest)
                guard let http = response as? HTTPURLResponse else {
                    throw HTTPError.invalidResponse
                }

                let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
                let level: DiagnosticLevel = http.statusCode >= 400 ? .warning : .debug
                await DiagnosticsCenter.shared.log(
                    level,
                    "network",
                    "\(target) -> \(http.statusCode) \(milliseconds)ms (attempt \(attempt))"
                )

                if retryPolicy.shouldRetry(statusCode: http.statusCode, attempt: attempt) {
                    let delay = retryPolicy.delay(forAttempt: attempt)
                    await DiagnosticsCenter.shared.log(
                        .warning,
                        "network",
                        "\(target) 重试 \(attempt + 1)/\(retryPolicy.maxAttempts)，"
                            + "\(delay)s 后（上次 HTTP \(http.statusCode)）"
                    )
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }

                var headers: [String: String] = [:]
                for (key, value) in http.allHeaderFields {
                    if let key = key as? String, let value = value as? String {
                        headers[key] = value
                    }
                }
                return HTTPResponse(statusCode: http.statusCode, data: data, headers: headers)
            } catch let error as HTTPError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if retryPolicy.shouldRetry(transportError: error, attempt: attempt) {
                    let delay = retryPolicy.delay(forAttempt: attempt)
                    await DiagnosticsCenter.shared.log(
                        .warning,
                        "network",
                        "\(target) 传输失败，重试 \(attempt + 1)/\(retryPolicy.maxAttempts)，"
                            + "\(delay)s 后：\(error.localizedDescription)"
                    )
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }

                await DiagnosticsCenter.shared.log(
                    .error,
                    "network",
                    "\(target) failed: \(error.localizedDescription)"
                )
                throw HTTPError.transport(error.localizedDescription)
            }
        }
    }
}
