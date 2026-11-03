import Foundation

public enum DiagnosticLevel: String, Codable, Sendable {
    case debug
    case info
    case warning
    case error
}

public struct DiagnosticEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: DiagnosticLevel
    public let category: String
    public let message: String

    public init(level: DiagnosticLevel, category: String, message: String) {
        id = UUID()
        timestamp = Date()
        self.level = level
        self.category = category
        self.message = message
    }
}

/// 本地滚动诊断日志（内存环形缓冲 + 导出）。
/// 规则：不落盘、不上传；导出前统一脱敏（Bearer token、签名参数）。
public actor DiagnosticsCenter {
    public static let shared = DiagnosticsCenter(maxEntries: 800)

    private let maxEntries: Int
    private var entries: [DiagnosticEntry] = []

    public init(maxEntries: Int) {
        self.maxEntries = maxEntries
    }

    public func log(_ level: DiagnosticLevel, _ category: String, _ message: String) {
        let entry = DiagnosticEntry(
            level: level,
            category: category,
            message: Redactor.scrub(message)
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func recent(limit: Int = 200) -> [DiagnosticEntry] {
        Array(entries.suffix(limit))
    }

    public func clear() {
        entries.removeAll()
    }

    /// 导出为临时 txt 文件（供系统分享）。
    public func exportFile() -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemonPlayerDiagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("diagnostics-\(Self.formatter.string(from: Date())).txt")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var text = "LemonPlayer Diagnostics\n\n"
        for entry in entries {
            text += "[\(formatter.string(from: entry.timestamp))] [\(entry.level.rawValue.uppercased())] [\(entry.category)] \(entry.message)\n"
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

/// 日志脱敏：token / 签名 / 查询参数。
public enum Redactor {
    public static func scrub(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"Bearer\s+[A-Za-z0-9._~+/=-]+"#,
            with: "Bearer ***",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)(token|sign|signature|auth|key|secret)=([^&\s\"]+)"#,
            with: "$1=***",
            options: .regularExpression
        )
        return result
    }
}
