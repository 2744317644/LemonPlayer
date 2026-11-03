import Foundation

/// 播放进度记录（断点续播）。v1 用 UserDefaults 持久化，数据量小；
/// 后续迁到 SwiftData 时保持本协议不变即可。
public struct PlaybackProgress: Codable, Sendable, Equatable {
    public let fileID: String
    public var position: TimeInterval
    public var duration: TimeInterval
    public var updatedAt: Date

    public init(fileID: String, position: TimeInterval, duration: TimeInterval, updatedAt: Date = Date()) {
        self.fileID = fileID
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }
}

public actor PlaybackProgressStore {
    private let defaults: UserDefaults
    private let storageKey = "lemonplayer.playback.progress"
    private let maxEntries = 300

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(_ progress: PlaybackProgress) {
        var map = loadMap()
        map[progress.fileID] = progress
        if map.count > maxEntries {
            let sorted = map.values.sorted { $0.updatedAt > $1.updatedAt }
            map = Dictionary(uniqueKeysWithValues: sorted.prefix(maxEntries).map { ($0.fileID, $0) })
        }
        persist(map)
    }

    public func progress(for fileID: String) -> PlaybackProgress? {
        loadMap()[fileID]
    }

    public func remove(fileID: String) {
        var map = loadMap()
        map.removeValue(forKey: fileID)
        persist(map)
    }

    public func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    public func recent(limit: Int = 20) -> [PlaybackProgress] {
        loadMap().values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Storage

    private func loadMap() -> [String: PlaybackProgress] {
        guard let data = defaults.data(forKey: storageKey),
              let map = try? JSONDecoder().decode([String: PlaybackProgress].self, from: data) else {
            return [:]
        }
        return map
    }

    private func persist(_ map: [String: PlaybackProgress]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
