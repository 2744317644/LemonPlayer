import Foundation

/// SRT / WebVTT / ASS(SSA) 解析。容错优先：坏行跳过，不因单条异常整份失败。
public enum SubtitleParser {
    public static func detectFormat(fileExtension: String?, text: String) -> SubtitleFormat {
        switch fileExtension?.lowercased() {
        case "srt": return .srt
        case "vtt": return .vtt
        case "ass", "ssa": return .ass
        default: break
        }

        let head = String(text.prefix(2048)).uppercased()
        if head.hasPrefix("WEBVTT") { return .vtt }
        if head.contains("[SCRIPT INFO]") || head.contains("[EVENTS]") { return .ass }
        if head.contains("-->") { return .srt }
        return .unknown
    }

    public static func parse(data: Data, fileExtension: String? = nil) throws -> SubtitleDocument {
        let decoded = SubtitleTextDecoder.decode(data)
        let format = detectFormat(fileExtension: fileExtension, text: decoded.text)
        let cues = parseCues(text: decoded.text, format: format)
        return SubtitleDocument(format: format, cues: cues, encoding: decoded.encoding)
    }

    public static func parseCues(text: String, format: SubtitleFormat) -> [SubtitleCue] {
        switch format {
        case .srt, .vtt:
            return parseTimedText(text)
        case .ass:
            return parseASS(text)
        case .unknown:
            return []
        }
    }

    // MARK: - SRT / WebVTT

    private static func parseTimedText(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var currentStart: TimeInterval?
        var currentEnd: TimeInterval?
        var buffer: [String] = []
        var index = 0

        func flush() {
            if let start = currentStart, let end = currentEnd, end > start {
                let body = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    cues.append(SubtitleCue(id: index, start: start, end: end, text: body))
                    index += 1
                }
            }
            currentStart = nil
            currentEnd = nil
            buffer = []
        }

        for rawLine in normalizeNewlines(text).split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let arrow = trimmed.range(of: "-->") {
                flush()
                currentStart = parseTimestamp(String(trimmed[..<arrow.lowerBound]))
                currentEnd = parseTimestamp(String(trimmed[arrow.upperBound...]))
            } else if trimmed.isEmpty {
                flush()
            } else if currentStart != nil {
                buffer.append(line)
            }
        }
        flush()
        return cues
    }

    /// 支持 `hh:mm:ss,mmm`、`hh:mm:ss.mmm`、`mm:ss.mmm`，并忽略 VTT 时间戳后的设置。
    static func parseTimestamp(_ raw: String) -> TimeInterval? {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if let space = value.firstIndex(of: " ") {
            value = String(value[..<space])
        }
        value = value.replacingOccurrences(of: ",", with: ".")
        let parts = value.split(separator: ":")
        guard parts.count >= 2, parts.count <= 3 else { return nil }

        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count else { return nil }

        switch numbers.count {
        case 3:
            return numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
        case 2:
            return numbers[0] * 60 + numbers[1]
        default:
            return nil
        }
    }

    // MARK: - ASS / SSA

    private static func parseASS(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var inEvents = false
        var index = 0

        for rawLine in normalizeNewlines(text).split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()

            if line.hasPrefix("[") {
                inEvents = lower == "[events]"
                continue
            }
            guard inEvents, lower.hasPrefix("dialogue:") else { continue }

            let body = String(line.dropFirst("dialogue:".count))
            let fields = body.split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
            guard fields.count == 10 else { continue }

            guard let start = parseASSTimestamp(String(fields[1])),
                  let end = parseASSTimestamp(String(fields[2])),
                  end > start else { continue }

            let rawText = String(fields[9])
                .replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
            let plain = stripASSTags(rawText).trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty {
                cues.append(SubtitleCue(id: index, start: start, end: end, text: plain))
                index += 1
            }
        }
        return cues
    }

    static func parseASSTimestamp(_ raw: String) -> TimeInterval? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        let parts = value.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    /// 去掉 ASS 的 `{...}` 覆盖标签，保留纯文本。
    static func stripASSTags(_ text: String) -> String {
        var output = ""
        var depth = 0
        for character in text {
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth = max(0, depth - 1)
            } else if depth == 0 {
                output.append(character)
            }
        }
        return output
    }

    private static func normalizeNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
