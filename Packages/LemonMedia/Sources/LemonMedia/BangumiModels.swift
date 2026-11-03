import Foundation

/// Bangumi v0 条目（subject）。
public struct BangumiSubject: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let nameCN: String?
    public let summary: String?
    public let date: String?
    public let eps: Int?
    public let totalEpisodes: Int?
    public let images: BangumiImages?
    public let rating: BangumiRating?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameCN = "name_cn"
        case summary
        case date
        case eps
        case totalEpisodes = "total_episodes"
        case images
        case rating
    }

    /// 优先中文名。
    public var displayName: String {
        if let nameCN, !nameCN.isEmpty { return nameCN }
        return name
    }

    public var coverURL: URL? {
        guard let raw = images?.large ?? images?.common ?? images?.medium ?? images?.grid else {
            return nil
        }
        return URL(string: raw)
    }
}

public struct BangumiImages: Decodable, Sendable, Equatable {
    public let large: String?
    public let common: String?
    public let medium: String?
    public let grid: String?
    public let small: String?
}

public struct BangumiRating: Decodable, Sendable, Equatable {
    public let score: Double?
    public let total: Int?
}

/// Bangumi 章节（episode）。
public struct BangumiEpisode: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let subjectID: Int?
    public let ep: Double?
    public let sort: Double?
    public let name: String?
    public let nameCN: String?
    public let airDate: String?
    public let type: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case subjectID = "subject_id"
        case ep
        case sort
        case name
        case nameCN = "name_cn"
        case airDate = "airdate"
        case type
    }

    public var displayName: String {
        let numbered = ep.map { "第\(Int($0))话" } ?? "第\(Int(sort ?? 0))话"
        if let nameCN, !nameCN.isEmpty { return "\(numbered) \(nameCN)" }
        if let name, !name.isEmpty { return "\(numbered) \(name)" }
        return numbered
    }
}
