import Foundation

/// 标题匹配：季数识别 + 相似度校验，避免把「第三季」匹配成「第二季」。
public enum TitleMatcher {
    private static let nonAnimeKeywords = [
        "live", "concert", "music video", "演唱", "音乐会", "歌曲", "谈话",
        "radio", "广播", "guitar hero", "吉他英雄", "making", "花絮", "专访",
    ]

    public static func looksLikeNonAnime(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return nonAnimeKeywords.contains { lowered.contains($0) }
    }

    /// 从标题提取季数：第三季 / Season 2 / S03 / ② / Ⅱ / ∬。
    public static func extractSeason(_ title: String) -> Int? {
        let patterns: [(String, Int?)] = [
            (#"第([0-9一二三四五六七八九十]+)季"#, nil),
            (#"(?i)\bseason\s*(\d{1,2})\b"#, nil),
            (#"(?i)\bs(\d{1,2})\b"#, nil),
            (#"②"#, 2), (#"③"#, 3), (#"④"#, 4), (#"Ⅱ"#, 2), (#"Ⅲ"#, 3), (#"∬"#, 2)
        ]
        for (pattern, fixed) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(title.startIndex..., in: title)
            guard let match = regex.firstMatch(in: title, range: range) else { continue }
            if let fixed { return fixed }
            guard match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: title) else { continue }
            let raw = String(title[captured])
            if let number = Int(raw) { return number }
            return chineseNumber(raw)
        }
        return nil
    }

    private static func chineseNumber(_ raw: String) -> Int? {
        let map: [Character: Int] = [
            "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
            "六": 6, "七": 7, "八": 8, "九": 9, "十": 10
        ]
        return map[raw.first ?? "x"]
    }

    public static func seasonMentioned(_ title: String, _ season: Int) -> Bool {
        var markers = ["第\(season)季", "Season \(season)", "S\(String(format: "%02d", season))", "S\(season)"]
        if season == 2 { markers += ["②", "Ⅱ", "∬", "第二季"] }
        if season == 3 { markers += ["③", "Ⅲ", "第三季"] }
        if season == 4 { markers += ["④", "Ⅳ", "第四季"] }
        return markers.contains { title.contains($0) }
    }

    /// 归一化后计算相似度（Levenshtein 距离的比例）。
    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        func normalize(_ text: String) -> String {
            let cleaned = SeriesFolderResolver.cleanTitle(text).lowercased()
            return cleaned.filter { $0.isLetter || $0.isNumber }
        }
        let a = Array(normalize(lhs))
        let b = Array(normalize(rhs))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        let distance = Double(previous[b.count])
        return 1 - distance / Double(max(a.count, b.count))
    }

    /// 在候选标题里选最匹配的一个；低相似度/错误季数返回 nil。
    public static func pickBest(title: String, candidates: [String]) -> Int? {
        let season = extractSeason(title)
        var bestIndex: Int?
        var bestScore = 0.0

        for (index, candidate) in candidates.enumerated() {
            var score = similarity(title, candidate)
            if let season, season > 1 {
                if seasonMentioned(candidate, season) {
                    score += 0.3
                } else if let other = [2, 3, 4, 5].first(where: { $0 != season && seasonMentioned(candidate, $0) }) {
                    _ = other
                    score -= 0.25
                }
            }
            if score > bestScore {
                bestIndex = index
                bestScore = score
            }
        }

        guard let bestIndex, bestScore >= 0.55 else { return nil }

        if let season, season > 1 {
            let candidate = candidates[bestIndex]
            // 想要第 N 季却匹配到没有季标记/其他季的条目：宁可判未匹配
            if !seasonMentioned(candidate, season) {
                return nil
            }
        }
        return bestIndex
    }
}
