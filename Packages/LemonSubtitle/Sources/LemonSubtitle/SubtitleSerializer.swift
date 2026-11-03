import Foundation

/// 把字幕条目序列化为 SRT（用于"时间轴校准"后重新注入内核）。
public enum SubtitleSerializer {
    /// - Parameter offset: 整体偏移（秒），正数表示字幕整体延后。
    public static func srt(from cues: [SubtitleCue], offset: TimeInterval = 0) -> String {
        var output = ""
        for (index, cue) in cues.enumerated() {
            let start = max(0, cue.start + offset)
            let end = max(start + 0.001, cue.end + offset)
            output += "\(index + 1)\n"
            output += "\(timestamp(start)) --> \(timestamp(end))\n"
            output += cue.text
            output += "\n\n"
        }
        return output
    }

    public static func timestamp(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let totalMilliseconds = Int((clamped * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secs = (totalMilliseconds % 60_000) / 1000
        let millis = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
}

/// ASS/SSA 时间轴偏移：只改 `Dialogue:` 行的时间戳，保留样式与文本标签。
public enum ASSSubtitleShifter {
    public static func shift(_ text: String, after offset: TimeInterval) -> String {
        guard offset != 0 else { return text }

        var lines: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let lower = line.lowercased()
            guard lower.hasPrefix("dialogue:") else {
                lines.append(line)
                continue
            }

            let prefixEnd = line.index(line.startIndex, offsetBy: "dialogue:".count)
            let body = String(line[prefixEnd...])
            let fields = body.split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
            guard fields.count == 10 else {
                lines.append(line)
                continue
            }

            let start = shiftedTimestamp(String(fields[1]), offset: offset)
            let end = shiftedTimestamp(String(fields[2]), offset: offset)
            let rebuilt = "Dialogue: " + [String(fields[0]), start, end]
                .joined(separator: ",") + "," + fields[3...].joined(separator: ",")
            lines.append(rebuilt)
        }
        return lines.joined(separator: "\n")
    }

    static func shiftedTimestamp(_ raw: String, offset: TimeInterval) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        let parts = value.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return raw
        }
        var total = hours * 3600 + minutes * 60 + seconds + offset
        total = max(0, total)
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let s = total - Double(h * 3600 + m * 60)
        return String(format: "%d:%02d:%05.2f", h, m, s)
    }
}
