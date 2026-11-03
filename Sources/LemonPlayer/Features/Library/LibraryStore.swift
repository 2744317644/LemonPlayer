import Foundation
import LemonMedia

/// 媒体库本地缓存（JSON 文件，Application Support）。
actor LibraryStore {
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("LemonPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("library.json")
    }

    func load() -> [LibrarySeries] {
        guard let data = try? Data(contentsOf: fileURL),
              let series = try? JSONDecoder().decode([LibrarySeries].self, from: data) else {
            return []
        }
        return series
    }

    func save(_ series: [LibrarySeries]) {
        guard let data = try? JSONEncoder().encode(series) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
