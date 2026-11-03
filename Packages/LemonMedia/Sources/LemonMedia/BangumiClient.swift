import Foundation
import LemonNetwork

/// Bangumi v0 公开接口客户端（无需登录）。
/// 注意：Bangumi 要求可识别 User-Agent；没有官方限流数值，这里自律 ≥1 秒/请求。
public actor BangumiClient {
    public static let baseURL = URL(string: "https://api.bgm.tv")!
    public static let defaultUserAgent = "LemonPlayer/0.1.0 (https://github.com/2744317644/LemonPlayer)"

    private let http: HTTPClient
    private let userAgent: String
    private let minimumInterval: TimeInterval
    private var lastRequestAt = Date.distantPast

    public init(
        http: HTTPClient = HTTPClient(),
        userAgent: String = BangumiClient.defaultUserAgent,
        minimumInterval: TimeInterval = 1.0
    ) {
        self.http = http
        self.userAgent = userAgent
        self.minimumInterval = minimumInterval
    }

    // MARK: - 搜索

    public func searchSubjects(keyword: String, limit: Int = 10, type: Int = 2) async throws -> [BangumiSubject] {
        struct Body: Encodable {
            struct Filter: Encodable {
                let type: [Int]
            }
            let keyword: String
            let filter: Filter
        }

        var components = URLComponents(url: Self.baseURL.appendingPathComponent("v0/search/subjects"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: "0")
        ]

        var headers = defaultHeaders
        headers["Content-Type"] = "application/json"
        let request = try HTTPRequest.json(
            url: components.url!,
            headers: headers,
            body: Body(keyword: keyword, filter: Body.Filter(type: [type]))
        )
        let response = try await send(request)
        guard response.isSuccess else {
            throw BangumiError.requestFailed(statusCode: response.statusCode)
        }
        struct Envelope: Decodable {
            let data: [BangumiSubject]
            let total: Int?
        }
        return try JSONDecoder().decode(Envelope.self, from: response.data).data
    }

    // MARK: - 详情

    public func subject(id: Int) async throws -> BangumiSubject {
        let request = HTTPRequest(
            url: Self.baseURL.appendingPathComponent("v0/subjects/\(id)"),
            headers: defaultHeaders
        )
        let response = try await send(request)
        guard response.isSuccess else {
            throw BangumiError.requestFailed(statusCode: response.statusCode)
        }
        return try JSONDecoder().decode(BangumiSubject.self, from: response.data)
    }

    // MARK: - 剧集

    /// 真实接口是 `/v0/episodes?subject_id=`（不是 `/subjects/{id}/episodes`，后者 404）。
    public func episodes(subjectID: Int, type: Int = 0, limit: Int = 100) async throws -> [BangumiEpisode] {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("v0/episodes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "subject_id", value: String(subjectID)),
            URLQueryItem(name: "type", value: String(type)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: "0")
        ]
        let request = HTTPRequest(url: components.url!, headers: defaultHeaders)
        let response = try await send(request)
        guard response.isSuccess else {
            throw BangumiError.requestFailed(statusCode: response.statusCode)
        }
        struct Envelope: Decodable {
            let data: [BangumiEpisode]
            let total: Int?
        }
        return try JSONDecoder().decode(Envelope.self, from: response.data).data
    }

    // MARK: - 内部

    private var defaultHeaders: [String: String] {
        ["User-Agent": userAgent, "Accept": "application/json"]
    }

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        await throttle()
        return try await http.send(request)
    }

    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequestAt)
        if elapsed < minimumInterval {
            try? await Task.sleep(for: .seconds(minimumInterval - elapsed))
        }
        lastRequestAt = Date()
    }
}

public enum BangumiError: Error, Equatable, Sendable {
    case requestFailed(statusCode: Int)

    public var localizedDescription: String {
        switch self {
        case .requestFailed(let statusCode):
            return "Bangumi 请求失败（HTTP \(statusCode)）"
        }
    }
}
