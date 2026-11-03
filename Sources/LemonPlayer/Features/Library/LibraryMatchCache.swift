import Foundation
import LemonMedia

/// 媒体库匹配缓存：避免每次扫描都请求 Bangumi（1 req/s 限流下扫描很慢）。
/// key 为规范化标题，TTL 30 天；命中失败的条目标记 7 天后再试。
actor LibraryMatchCache {
    private struct Entry: Codable {
        let match: LibraryMatch?
        let savedAt: Date
    }

    private let fileURL: URL
    private var entries: [String: Entry] = [:]
    private let successTTL: TimeInterval = 30 * 24 * 3600
    private let missTTL: TimeInterval = 7 * 24 * 3600

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("LemonPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("match-cache.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    func cached(for title: String) -> LibraryMatch? {
        let key = normalize(title)
        guard let entry = entries[key] else { return nil }
        let ttl = entry.match == nil ? missTTL : successTTL
        guard Date().timeIntervalSince(entry.savedAt) < ttl else {
            entries[key] = nil
            return nil
        }
        return entry.match
    }

    func store(_ match: LibraryMatch?, for title: String) {
        entries[normalize(title)] = Entry(match: match, savedAt: Date())
        if entries.count > 2000 {
            let oldest = entries.sorted { $0.value.savedAt < $1.value.savedAt }.prefix(500)
            for (key, _) in oldest {
                entries[key] = nil
            }
        }
        persist()
    }

    private func normalize(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
