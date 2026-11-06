import Foundation

public enum SubtitleLanguage: String, Sendable, CaseIterable {
    case chineseSimplified
    case chineseTraditional
    case japanese
    case english
    case unknown

    public var displayName: String {
        switch self {
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁体中文"
        case .japanese: return "日语"
        case .english: return "英语"
        case .unknown: return "未知"
        }
    }
}

public struct SubtitleCandidate: Identifiable, Equatable, Sendable {
    public let fileName: String
    public let language: SubtitleLanguage
    public let format: SubtitleFormat
    public let score: Int
    public let episodeNumber: Int?

    public var id: String { fileName }

    public init(
        fileName: String,
        language: SubtitleLanguage,
        format: SubtitleFormat,
        score: Int,
        episodeNumber: Int?
    ) {
        self.fileName = fileName
        self.language = language
        self.format = format
        self.score = score
        self.episodeNumber = episodeNumber
    }
}

/// 外挂字幕同名匹配。
/// 规则：规范化基础名（去扩展名/字幕组标签/分辨率/编码）+ 集号校验 + 语言后缀识别 + 格式优先级。
public enum SubtitleMatcher {
    private static let noiseTokens: Set<String> = [
        "1080p", "720p", "2160p", "480p", "4k", "8k",
        "x264", "x265", "h264", "h265", "hevc", "avc", "10bit", "8bit", "hdr", "hdr10", "sdr",
        "aac", "ac3", "eac3", "dts", "flac", "opus", "truehd",
        "web", "webdl", "web-dl", "webrip", "bluray", "bdrip", "brrip", "hdtv", "dvdrip", "remux",
        "chs", "cht", "sc", "tc", "gb", "big5", "jpn", "eng", "ja", "en",
        "简体", "繁体", "简中", "繁中", "双语", "字幕", "内嵌", "外挂", "日语", "英语", "中文"
    ]

    public static func candidates(videoName: String, subtitleNames: [String]) -> [SubtitleCandidate] {
        let videoBase = normalizedBase(videoName)
        let videoEpisode = episodeNumber(in: videoName)

        var results: [SubtitleCandidate] = []
        for name in subtitleNames {
            guard isSubtitleFile(name) else { continue }
            let base = normalizedBase(name)
            guard !base.isEmpty else { continue }

            let episode = episodeNumber(in: name)
            if let videoEpisode, let episode, videoEpisode != episode {
                continue // 集号明确不一致：直接排除
            }

            var score = 0
            if base == videoBase {
                score = 100
            } else if base.hasPrefix(videoBase) || videoBase.hasPrefix(base) {
                score = 80
            } else if base.contains(videoBase) || videoBase.contains(base) {
                score = 60
            } else {
                // 去掉集号后比较（同名不同集号的常见情形）
                let strippedBase = removingEpisode(base)
                let strippedVideo = removingEpisode(videoBase)
                if !strippedBase.isEmpty, strippedBase == strippedVideo {
                    score = 70
                }
            }

            guard score > 0 else { continue }
            if episode != nil, videoEpisode != nil {
                score += 10 // 集号一致加成
            }

            let format = formatOf(name)
            if format == .ass { score += 3 }
            if format == .srt { score += 2 }

            results.append(
                SubtitleCandidate(
                    fileName: name,
                    language: languageOf(name),
                    format: format,
                    score: score,
                    episodeNumber: episode
                )
            )
        }

        return results.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            // 同分时按语言偏好：简中 > 繁中 > 未知 > 日语 > 英语
            let lhs = languagePriority($0.language)
            let rhs = languagePriority($1.language)
            if lhs != rhs { return lhs > rhs }
            return $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
    }

    // MARK: - 规范化

    public static func normalizedBase(_ name: String) -> String {
        var value = name
        if let dot = value.lastIndex(of: ".") {
            let ext = value[value.index(after: dot)...].lowercased()
            if ["srt", "vtt", "ass", "ssa", "mkv", "mp4", "avi", "ts", "m4v", "mov", "webm"].contains(ext) {
                value = String(value[..<dot])
            }
        }

        value = value.lowercased()
        for separator in ["[", "]", "(", ")", "{", "}", "_", ".", "-", "+", "【", "】", "「", "」"] {
            value = value.replacingOccurrences(of: separator, with: " ")
        }

        let tokens = value
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
            .filter { token in
                if noiseTokens.contains(token) { return false }
                if token.wholeMatch(of: /\d{3,4}[pi]/) != nil { return false }
                return true
            }

        let joined = tokens.joined()
        return joined.replacingOccurrences(of: " ", with: "")
    }

    public static func removingEpisode(_ base: String) -> String {
        var value = base
        if let range = value.firstRange(of: /\d{1,4}(?=$)/) {
            value.removeSubrange(range)
        }
        return value
    }

    // MARK: - 集号 / 语言 / 格式

    public static func episodeNumber(in name: String) -> Int? {
        let lower = name.lowercased()

        if let match = lower.firstMatch(of: /s\d{1,2}e(\d{1,4})/) {
            return Int(match.1)
        }
        if let match = lower.firstMatch(of: /(?:^|[^a-z])e(?:p)?\.?\s?(\d{1,4})(?![0-9])/) {
            return Int(match.1)
        }
        if let match = name.firstMatch(of: /第\s?(\d{1,4})\s?[话話集]/) {
            return Int(match.1)
        }
        if let match = name.firstMatch(of: /\[(\d{1,4})(?:v\d)?\]/) {
            return Int(match.1)
        }
        if let match = lower.firstMatch(of: /(?:^|[^0-9])(\d{2,3})(?![0-9])(?:[^0-9]|$)/) {
            let value = Int(match.1)
            if let value, (1...999).contains(value) {
                return value
            }
        }
        return nil
    }

    public static func languageOf(_ name: String) -> SubtitleLanguage {
        let lower = name.lowercased()
        let tokens = lower
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)

        for token in tokens {
            switch token {
            case "chs", "sc", "zhcn", "zh-cn", "gb", "cn", "简体", "简中":
                return .chineseSimplified
            case "cht", "tc", "zhtw", "zh-tw", "big5", "tw", "hk", "繁体", "繁中":
                return .chineseTraditional
            case "jpn", "jp", "ja", "日语":
                return .japanese
            case "eng", "en", "英语":
                return .english
            default:
                continue
            }
        }
        return .unknown
    }

    /// 同分时的语言偏好（越大越优先）。
    public static func languagePriority(_ language: SubtitleLanguage) -> Int {
        switch language {
        case .chineseSimplified: return 5
        case .chineseTraditional: return 4
        case .unknown: return 3
        case .japanese: return 2
        case .english: return 1
        }
    }

    public static func formatOf(_ name: String) -> SubtitleFormat {
        switch name.split(separator: ".").last?.lowercased() {
        case "srt": return .srt
        case "vtt": return .vtt
        case "ass", "ssa": return .ass
        default: return .unknown
        }
    }

    public static func isSubtitleFile(_ name: String) -> Bool {
        formatOf(name) != .unknown
    }
}
