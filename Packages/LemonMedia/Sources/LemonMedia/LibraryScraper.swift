import Foundation

/// 刮削输入：来自网盘的视频文件。
public struct VideoFile: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let parentID: String

    public init(id: String, name: String, parentID: String) {
        self.id = id
        self.name = name
        self.parentID = parentID
    }
}

/// 剧集条目（一个文件的映射）。
public struct SeriesEpisode: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let episode: Int?
    public let fileName: String
    public let parentID: String

    public init(id: String, episode: Int?, fileName: String, parentID: String) {
        self.id = id
        self.episode = episode
        self.fileName = fileName
        self.parentID = parentID
    }

    public var displayName: String {
        if let episode { return "第\(episode)话" }
        return fileName
    }
}

/// 媒体库中的一个系列（Bangumi 条目 + 本地文件映射）。
public struct LibrarySeries: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let bangumiID: Int?
    public let coverURL: String?
    public let year: Int?
    public let score: Double?
    public let episodes: [SeriesEpisode]

    public init(
        id: String,
        title: String,
        bangumiID: Int? = nil,
        coverURL: String? = nil,
        year: Int? = nil,
        score: Double? = nil,
        episodes: [SeriesEpisode]
    ) {
        self.id = id
        self.title = title
        self.bangumiID = bangumiID
        self.coverURL = coverURL
        self.year = year
        self.score = score
        self.episodes = episodes
    }
}

/// Bangumi 匹配结果（由客户端填充，便于测试注入）。
public struct LibraryMatch: Sendable, Equatable, Codable {
    public let bangumiID: Int?
    public let title: String
    public let coverURL: String?
    public let year: Int?
    public let score: Double?

    public init(bangumiID: Int?, title: String, coverURL: String?, year: Int?, score: Double?) {
        self.bangumiID = bangumiID
        self.title = title
        self.coverURL = coverURL
        self.year = year
        self.score = score
    }
}

/// 刮削编排：文件名解析 → 按标题/季分组 → Bangumi 匹配 → 生成媒体库条目。
public enum LibraryScraper {
    public struct Group: Sendable, Equatable {
        public let key: String
        public let title: String
        public let season: Int?
        public let files: [VideoFile]
    }

    /// 分组：同一标题 + 同一季归为一个系列。
    public static func group(_ files: [VideoFile]) -> [Group] {
        var buckets: [String: [VideoFile]] = [:]
        var meta: [String: (title: String, season: Int?)] = [:]

        for file in files {
            let parsed = MediaNameParser.parse(file.name)
            guard !parsed.title.isEmpty else { continue }
            let normalized = parsed.title
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
            let season = parsed.season ?? 1
            let key = "\(normalized)#\(season)"
            buckets[key, default: []].append(file)
            if meta[key] == nil {
                meta[key] = (parsed.title, parsed.season)
            }
        }

        return buckets.keys.sorted().map { key in
            let info = meta[key] ?? ("", nil)
            return Group(
                key: key,
                title: info.title,
                season: info.season,
                files: buckets[key] ?? []
            )
        }
    }

    /// 批量刮削。`match` 由调用方提供（生产环境调 Bangumi，测试注入桩）。
    /// `onProgress` 在每个分组开始前回传 (已完成, 总数)，用于扫描进度条。
    public static func build(
        files: [VideoFile],
        onProgress: (@Sendable (Int, Int) -> Void)? = nil,
        match: @Sendable (String) async -> LibraryMatch?
    ) async -> [LibrarySeries] {
        var results: [LibrarySeries] = []
        let groups = group(files)
        for (index, group) in groups.enumerated() {
            if Task.isCancelled { break }
            onProgress?(index, groups.count)
            let matched = await match(group.title)
            let episodes = group.files
                .map { file -> SeriesEpisode in
                    let parsed = MediaNameParser.parse(file.name)
                    return SeriesEpisode(
                        id: file.id,
                        episode: parsed.episode,
                        fileName: file.name,
                        parentID: file.parentID
                    )
                }
                .sorted {
                    if ($0.episode ?? Int.max) != ($1.episode ?? Int.max) {
                        return ($0.episode ?? Int.max) < ($1.episode ?? Int.max)
                    }
                    return $0.fileName < $1.fileName
                }

            let title = matched?.title ?? group.title
            let seriesID = matched?.bangumiID.map(String.init) ?? group.key
            results.append(
                LibrarySeries(
                    id: seriesID,
                    title: title,
                    bangumiID: matched?.bangumiID,
                    coverURL: matched?.coverURL,
                    year: matched?.year,
                    score: matched?.score,
                    episodes: episodes
                )
            )
        }
        return results.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
