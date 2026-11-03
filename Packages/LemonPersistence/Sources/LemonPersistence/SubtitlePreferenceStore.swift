import Foundation
import LemonSubtitle

/// 每个文件记住的字幕选择与偏移（按 fileID）。
public struct SubtitlePreference: Codable, Sendable, Equatable {
    public var primaryFileName: String?
    public var secondaryFileName: String?
    public var offset: TimeInterval

    public init(primaryFileName: String? = nil, secondaryFileName: String? = nil, offset: TimeInterval = 0) {
        self.primaryFileName = primaryFileName
        self.secondaryFileName = secondaryFileName
        self.offset = offset
    }
}

public actor SubtitlePreferenceStore {
    private let defaults: UserDefaults
    private let storageKey = "lemonplayer.subtitle.preference"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func preference(for fileID: String) -> SubtitlePreference? {
        loadMap()[fileID]
    }

    public func save(_ preference: SubtitlePreference, for fileID: String) {
        var map = loadMap()
        map[fileID] = preference
        persist(map)
    }

    public func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    private func loadMap() -> [String: SubtitlePreference] {
        guard let data = defaults.data(forKey: storageKey),
              let map = try? JSONDecoder().decode([String: SubtitlePreference].self, from: data) else {
            return [:]
        }
        return map
    }

    private func persist(_ map: [String: SubtitlePreference]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

/// 全局字幕样式。
public actor SubtitleStyleStore {
    private let defaults: UserDefaults
    private let storageKey = "lemonplayer.subtitle.style"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> SubtitleStyle {
        guard let data = defaults.data(forKey: storageKey),
              let style = try? JSONDecoder().decode(SubtitleStyle.self, from: data) else {
            return .default
        }
        return style
    }

    public func save(_ style: SubtitleStyle) {
        guard let data = try? JSONEncoder().encode(style) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
