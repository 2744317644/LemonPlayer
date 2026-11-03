import Foundation

enum Formatters {
    static func fileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }

    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func subtitle(for file: GuangyaFile) -> String {
        let parts = [fileSize(file.size), relativeDate(file.modifiedAt)].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}
