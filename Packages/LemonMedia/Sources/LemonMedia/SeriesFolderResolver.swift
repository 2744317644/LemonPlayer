import Foundation

/// 媒体库目录节点（只保留解析所需的三个字段）。
public struct LibraryFolderNode: Codable, Hashable, Sendable {
    public let id: String
    public let parentID: String
    public let name: String

    public init(id: String, parentID: String, name: String) {
        self.id = id
        self.parentID = parentID
        self.name = name
    }
}

/// 剧集目录解析：以「最底层文件夹」作为一部番剧，
/// 遇到 Fonts / OP / ED / SPs / Scans 等附属目录时向上取父目录。
public enum SeriesFolderResolver {
    /// 附属目录（番剧本体不在这些目录里）；按“词”匹配，避免误伤含 op/ed 的英文名。
    private static let noiseTokens: Set<String> = [
        "font", "fonts", "op", "ops", "ed", "eds", "oped", "opeds",
        "sp", "sps", "special", "specials", "ncop", "nced", "nc", "menu",
        "scan", "scans", "cd", "cds", "ost", "soundtrack", "music", "mv",
        "pv", "preview", "cm", "extras", "extra", "bonus", "tokuten",
        "sub", "subs", "subtitle", "subtitles", "booklet", "artbook", "art",
        "creditless", "clean", "logo", "trailer", "teaser", "sample"
    ]

    /// 中文附属目录关键词（包含匹配）。
    private static let noiseChineseKeywords: [String] = [
        "字体", "字幕", "特典", "映像", "番外", "原声", "画集", "周边", "歌词",
        "歌詞", "预告", "花絮", "扫描", "扫图", "音乐", "菜单"
    ]

    /// 季目录（如 Season 1 / S02 / 第二季）不是番剧本体。
    private static func isSeasonFolder(_ name: String) -> Bool {
        let lowered = name.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
        if lowered.range(of: #"^(season|s)\d{1,2}$"#, options: .regularExpression) != nil {
            return true
        }
        return lowered.range(of: #"^第[0-9一二三四五六七八九十]+季$"#, options: .regularExpression) != nil
    }

    /// 分辨率/编码/语言之类的“包装目录”，也应向上取父目录。
    private static func isQualityFolder(_ name: String) -> Bool {
        let lowered = name.lowercased()
        let qualityTokens = [
            "1080p", "720p", "2160p", "480p", "4k", "8bit", "10bit",
            "hevc", "avc", "x264", "x265", "h264", "h265", "bdrip", "webrip",
            "web-dl", "webdl", "bluray", "blu-ray", "flac", "aac", "chs", "cht",
            "gb", "big5", "简繁", "简中", "繁中", "内封", "内嵌", "外挂", "双语"
        ]
        let stripped = lowered
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let words = stripped.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty else { return false }
        // 目录里绝大多数词都是画质/编码标签时视为包装目录
        let hits = words.filter { word in
            qualityTokens.contains(word) || word.range(of: #"^\d{3,4}p$"#, options: .regularExpression) != nil
        }
        return hits.count >= max(1, words.count - 1)
    }

    /// 判断目录名是否是番剧附属目录。
    public static func isNoiseFolder(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        for keyword in noiseChineseKeywords where trimmed.contains(keyword) {
            return true
        }

        let tokens = trimmed.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        if !tokens.isEmpty, tokens.allSatisfy({ noiseTokens.contains($0) }) {
            return true
        }
        // 单个词（如 OP、Fonts）也直接命中
        if tokens.count == 1, let token = tokens.first, noiseTokens.contains(token) {
            return true
        }
        return false
    }

    /// 从文件所在目录向上回溯，返回最底层的“番剧目录”。
    public static func resolveSeriesFolder(
        forFileParent parentID: String,
        folders: [String: LibraryFolderNode],
        maxDepth: Int = 8
    ) -> LibraryFolderNode? {
        var currentID = parentID
        var depth = 0
        var lastSeen: LibraryFolderNode?

        while depth < maxDepth, !currentID.isEmpty, let node = folders[currentID] {
            lastSeen = node
            if isNoiseFolder(node.name) || isSeasonFolder(node.name) || isQualityFolder(node.name) {
                currentID = node.parentID
                depth += 1
                continue
            }
            return node
        }
        // 走到根（或超过深度）时，用最后见到的目录兜底
        return lastSeen
    }

    /// 把目录名清洗成可搜索的标题：去组名/画质/季集标记。
    public static func cleanTitle(_ raw: String) -> String {
        var text = raw

        // 去掉 [] （） () 【】 内的信息（字幕组、画质、来源等）
        for pattern in [#"\[[^\]]*\]"#, #"\([^)]*\)"#, #"【[^】]*】"#, #"（[^）]*）"#] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        // 去画质/编码/来源标记
        text = text.replacingOccurrences(
            of: #"(?i)\b(\d{3,4}p|4k|8bit|10bit|hevc|avc|x264|x265|h264|h265|bdrip|webrip|web-dl|bluray|flac|aac|chs|cht)\b"#,
            with: " ",
            options: .regularExpression
        )
        // 保留季标记（第三季 / S01 / Season 1），匹配时需要它来区分季度
        text = text.replacingOccurrences(of: "_", with: " ")
        text = text.replacingOccurrences(of: ".", with: " ")

        // 收尾：去多余空格与符号（保留 ! ? 等标题标点，避免 MyGO!!!!! 被截断）
        text = text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-–—~·:：,，"))
        if !trimmed.isEmpty {
            return trimmed
        }

        // 整个目录名都在括号里（如 [DBD-Raws][葬送的芙莉莲][1080P]）：
        // 取最长的非附属/非画质括号内容作为标题
        let pattern = #"[\[【（(]([^\]】）)]+)[\]】）)]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let ns = raw as NSString
        let candidates = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
        let best = candidates
            .filter { !isNoiseFolder($0) && !isQualityFolder($0) }
            .max { lhs, rhs in
                scoreTitleCandidate(lhs) < scoreTitleCandidate(rhs)
            }
        return best ?? raw
    }

    /// 括号候选评分：含中日文 > 含空格 > 更长，避免选到 DBD-Raws 这类组名。
    private static func scoreTitleCandidate(_ candidate: String) -> Int {
        var score = candidate.count
        if candidate.range(of: #"\p{Han}"#, options: .regularExpression) != nil {
            score += 20
        }
        if candidate.contains(" ") {
            score += 5
        }
        return score
    }
}
