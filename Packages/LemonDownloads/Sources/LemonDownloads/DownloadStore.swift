import Foundation

/// 下载记录持久化（JSON + 断点数据文件）。
public struct DownloadStore: Sendable {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("LemonPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("downloads.json")
    }

    public var downloadsDirectory: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("Downloads", isDirectory: true)
    }

    public var resumeDataDirectory: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("ResumeData", isDirectory: true)
    }

    public func load() -> [DownloadRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([DownloadRecord].self, from: data) else {
            return []
        }
        return records
    }

    public func save(_ records: [DownloadRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - 断点数据持久化（App 重启后仍可续传）

    public func saveResumeData(_ data: Data, id: String) {
        try? FileManager.default.createDirectory(at: resumeDataDirectory, withIntermediateDirectories: true)
        try? data.write(to: resumeDataURL(id: id), options: .atomic)
    }

    public func resumeData(id: String) -> Data? {
        try? Data(contentsOf: resumeDataURL(id: id))
    }

    public func removeResumeData(id: String) {
        try? FileManager.default.removeItem(at: resumeDataURL(id: id))
    }

    private func resumeDataURL(id: String) -> URL {
        resumeDataDirectory.appendingPathComponent("\(id).resume")
    }
}
