import Foundation

/// ASS/SSA 自定义字体库：导入的字体文件放在 Application Support/LemonPlayer/Fonts，
/// 播放时通过 VLCKit `:sub-fonts-dir=` 交给 libass，特效字幕的字体族即可正确命中。
enum SubtitleFontStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base
            .appendingPathComponent("LemonPlayer", isDirectory: true)
            .appendingPathComponent("Fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static var count: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
    }

    static func installedFontNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .sorted()
    }

    /// 复制用户选择的字体文件（支持安全作用域 URL）。
    @discardableResult
    static func importFont(from url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let destination = directory.appendingPathComponent(url.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return url.lastPathComponent
        } catch {
            return nil
        }
    }

    static func removeAll() {
        for name in installedFontNames() {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
