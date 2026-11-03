import Foundation

/// 从文件名解析出的媒体信息（用于 Bangumi 搜索与剧集识别）。
public struct ParsedMediaName: Equatable, Sendable {
    public let title: String
    public let year: Int?
    public let season: Int?
    public let episode: Int?
    public let resolution: String?
    public let isMovie: Bool

    public init(
        title: String,
        year: Int? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        resolution: String? = nil,
        isMovie: Bool = false
    ) {
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
        self.resolution = resolution
        self.isMovie = isMovie
    }

    public var searchQuery: String { title }
}

/// 常见动漫/影视命名解析：
/// `[字幕组] 标题 - 01 [1080p].mkv`、`Show.S02E05.1080p.mkv`、`进击的巨人 第二季 第05话.mkv`、`电影 (2024).mkv`
public enum MediaNameParser {
    private static let videoExtensions: Set<String> = ["mkv", "mp4", "avi", "ts", "m4v", "mov", "webm", "rmvb", "flv", "wmv"]

    public static func parse(_ fileName: String) -> ParsedMediaName {
        var name = fileName
        if let dot = name.lastIndex(of: ".") {
            let ext = name[name.index(after: dot)...].lowercased()
            if videoExtensions.contains(ext) {
                name = String(name[..<dot])
            }
        }

        let resolution = detectResolution(in: name)
        let year = detectYear(in: name)
        let season = detectSeason(in: name)
        let episode = detectEpisode(in: name)
        let isMovie = episode == nil && !name.lowercased().contains("tv")

        var title = name
        title = removeBracketTags(title)
        title = cutAtSeasonOrEpisode(title)
        title = title
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        if let year, let range = title.range(of: String(year)) {
            title = String(title[..<range.lowerBound])
        }
        title = title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "[]()【】·・:：")))

        return ParsedMediaName(
            title: title.isEmpty ? name : title,
            year: year,
            season: season,
            episode: episode,
            resolution: resolution,
            isMovie: isMovie
        )
    }

    // MARK: - 探测

    public static func detectResolution(in name: String) -> String? {
        let lower = name.lowercased()
        for token in ["4320p", "2160p", "1080p", "720p", "480p", "8k", "4k"] {
            if lower.contains(token) { return token }
        }
        return nil
    }

    public static func detectYear(in name: String) -> Int? {
        guard let range = name.range(of: #"(19|20)\d{2}"#, options: .regularExpression) else {
            return nil
        }
        return Int(name[range])
    }

    public static func detectSeason(in name: String) -> Int? {
        let lower = name.lowercased()
        if let match = lower.firstMatch(of: /s(\d{1,2})[ ._-]?e\d{1,4}/) {
            return Int(match.1)
        }
        if let match = name.firstMatch(of: /第\s?([一二三四五六七八九十\d]{1,3})\s?[季期]/) {
            return chineseNumber(match.1)
        }
        if let match = lower.firstMatch(of: /[ ._-]s(\d{1,2})(?:[^0-9e]|$)/) {
            return Int(match.1)
        }
        if let match = lower.firstMatch(of: /season[ ._-]?(\d{1,2})/) {
            return Int(match.1)
        }
        return nil
    }

    public static func detectEpisode(in name: String) -> Int? {
        let lower = name.lowercased()
        if let match = lower.firstMatch(of: /s\d{1,2}[ ._-]?e(\d{1,4})/) {
            return Int(match.1)
        }
        if let match = name.firstMatch(of: /第\s?(\d{1,4})\s?[话話集]/) {
            return Int(match.1)
        }
        if let match = name.firstMatch(of: /\[(\d{1,4})(?:v\d)?\]/) {
            return Int(match.1)
        }
        if let match = lower.firstMatch(of: /[ ._-]e(?:p)?[ ._-]?(\d{1,4})(?:[^0-9]|$)/) {
            return Int(match.1)
        }
        // 常见 " - 01" 形式
        if let match = name.firstMatch(of: /\s-\s(\d{1,4})(?:v\d)?(?:\s|$|\[)/) {
            return Int(match.1)
        }
        return nil
    }

    // MARK: - 清理

    private static func removeBracketTags(_ name: String) -> String {
        var result = name
        for pattern in [#"\[[^\]]*\]"#, #"【[^】]*】"#] {
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return result
    }

    private static func cutAtSeasonOrEpisode(_ title: String) -> String {
        var cut = title
        let markers = [
            #"第\s?[一二三四五六七八九十\d]{1,3}\s?[季期]"#,
            #"第\s?\d{1,4}\s?[话話集]"#,
            #"[Ss]\d{1,2}[ ._-]?[Ee]\d{1,4}"#,
            #"\s-\s\d{1,4}"#
        ]
        for marker in markers {
            if let range = cut.range(of: marker, options: .regularExpression) {
                cut = String(cut[..<range.lowerBound])
            }
        }
        return cut
    }

    private static func chineseNumber(_ text: Substring) -> Int? {
        if let value = Int(text) { return value }
        let map: [Character: Int] = [
            "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
            "六": 6, "七": 7, "八": 8, "九": 9, "十": 10
        ]
        guard let first = text.first, let value = map[first] else { return nil }
        return value
    }
}
