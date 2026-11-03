import Foundation

/// 媒体库匹配缓存：避免每次扫描都请求 Bangumi/TMDB（限流 1 req/s 时很慢）。
/// - 命中结果的 TTL 默认 30 天；未命中的 TTL 默认 7 天（避免反复请求不存在的标题）。
/// - 标题 key 做小写 + 去空格/下划线归一化。
/// - 条目数超过上限时按最旧写入清理 25%。
public actor LibraryMatchCache {
    public struct Configuration: Sendable {
        public var successTTL: TimeInterval
        public var missTTL: TimeInterval
        public var maxEntries: Int

        public init(
            successTTL: TimeInterval = 30 * 24 * 3600,
            missTTL: TimeInterval = 7 * 24 * 3600,
            maxEntries: Int = 2000
        ) {
            self.successTTL = successTTL
            self.missTTL = missTTL
            self.maxEntries = maxEntries
        }

        public static let `default` = Configuration()
    }

    public enum Lookup: Sendable {
        case match(LibraryMatch)
        case miss
    }

    private struct Entry: Codable {
        let match: LibraryMatch?
        let savedAt: Date
    }

    private let fileURL: URL
    private let configuration: Configuration
    private var entries: [String: Entry]

    public init(directory: URL? = nil, configuration: Configuration = .default) {
        self.configuration = configuration

        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("LemonPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("match-cache.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    public func lookup(for title: String, now: Date = Date()) -> Lookup? {
        let key = Self.normalize(title)
        guard let entry = entries[key] else { return nil }

        let ttl = entry.match == nil ? configuration.missTTL : configuration.successTTL
        guard now.timeIntervalSince(entry.savedAt) < ttl else {
            entries[key] = nil
            return nil
        }
        if let match = entry.match {
            return .match(match)
        }
        return .miss
    }

    public func store(_ match: LibraryMatch?, for title: String, now: Date = Date()) {
        entries[Self.normalize(title)] = Entry(match: match, savedAt: now)
        trimIfNeeded()
        persist()
    }

    public func count() -> Int { entries.count }

    public static func normalize(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private func trimIfNeeded() {
        guard entries.count > configuration.maxEntries else { return }
        let overflow = entries.count - configuration.maxEntries
        let removeCount = max(overflow, configuration.maxEntries / 4)
        let oldest = entries.sorted { $0.value.savedAt < $1.value.savedAt }.prefix(removeCount)
        for (key, _) in oldest {
            entries[key] = nil
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
