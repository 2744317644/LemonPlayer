import Foundation
import LemonNetwork

/// TMDB v3 客户端：作为 Bangumi 匹配失败（真人影视/番剧名识别不到）时的兜底海报源。
/// API Key 由用户在设置中填写，仅保存在本机。
public struct TMDBClient: Sendable {
    public static let baseURL = URL(string: "https://api.themoviedb.org/3")!
    public static let imageBaseURL = URL(string: "https://image.tmdb.org/t/p/w500")!

    private let http: HTTPClient
    private let apiKey: String

    public init(apiKey: String, http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.http = http
    }

    public var isConfigured: Bool { !apiKey.isEmpty }

    public func search(_ query: String, language: String = "zh-CN") async throws -> [TMDBSearchResult] {
        guard isConfigured else { return [] }

        var components = URLComponents(url: Self.baseURL.appendingPathComponent("search/multi"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "include_adult", value: "false")
        ]

        let response = try await http.send(HTTPRequest(url: components.url!))
        guard response.isSuccess else {
            throw TMDBError.requestFailed(statusCode: response.statusCode)
        }
        struct Envelope: Decodable {
            let results: [TMDBSearchResult]
        }
        return try JSONDecoder().decode(Envelope.self, from: response.data).results
    }

    public static func posterURL(for path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: path.hasPrefix("/") ? "https://image.tmdb.org/t/p/w500\(path)" : path)
    }
}

public struct TMDBSearchResult: Decodable, Sendable, Equatable {
    public let id: Int
    public let mediaType: String?
    public let title: String?
    public let name: String?
    public let releaseDate: String?
    public let firstAirDate: String?
    public let posterPath: String?
    public let voteAverage: Double?
    public let overview: String?

    enum CodingKeys: String, CodingKey {
        case id
        case mediaType = "media_type"
        case title
        case name
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case overview
    }

    public var displayTitle: String {
        title ?? name ?? "未命名"
    }

    public var year: Int? {
        let raw = releaseDate ?? firstAirDate
        guard let raw, raw.count >= 4 else { return nil }
        return Int(String(raw.prefix(4)))
    }

    public var posterURL: URL? {
        TMDBClient.posterURL(for: posterPath)
    }
}

public enum TMDBError: Error, Equatable, Sendable {
    case requestFailed(statusCode: Int)

    public var localizedDescription: String {
        switch self {
        case .requestFailed(let statusCode):
            return "TMDB 请求失败（HTTP \(statusCode)）"
        }
    }
}
