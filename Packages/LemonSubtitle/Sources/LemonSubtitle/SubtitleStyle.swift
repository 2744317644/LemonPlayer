import Foundation

/// 字幕显示样式（SRT/VTT 自绘 overlay 生效；ASS 走 libass 原生渲染）。
public struct SubtitleStyle: Codable, Sendable, Equatable {
    public var fontSize: Double
    /// 十六进制颜色，如 "#FFFFFF"
    public var textColorHex: String
    public var outlineColorHex: String
    public var outlineWidth: Double
    public var backgroundOpacity: Double
    public var bottomInset: Double

    public init(
        fontSize: Double = 22,
        textColorHex: String = "#FFFFFF",
        outlineColorHex: String = "#000000",
        outlineWidth: Double = 2,
        backgroundOpacity: Double = 0,
        bottomInset: Double = 64
    ) {
        self.fontSize = fontSize
        self.textColorHex = textColorHex
        self.outlineColorHex = outlineColorHex
        self.outlineWidth = outlineWidth
        self.backgroundOpacity = backgroundOpacity
        self.bottomInset = bottomInset
    }

    public static let `default` = SubtitleStyle()
}

/// 字幕时间轴查询：按播放时间找出当前应显示的条目。
public enum SubtitleTimeline {
    public static func activeCues(in cues: [SubtitleCue], at time: TimeInterval) -> [SubtitleCue] {
        guard !cues.isEmpty else { return [] }
        // 二分找到最后一个 start <= time 的位置，再向前回扫（通常只有 1-2 条重叠）
        var low = 0
        var high = cues.count - 1
        var candidate = -1
        while low <= high {
            let mid = (low + high) / 2
            if cues[mid].start <= time {
                candidate = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard candidate >= 0 else { return [] }

        var result: [SubtitleCue] = []
        var index = candidate
        while index >= 0, cues[candidate].start - cues[index].start < 10 {
            let cue = cues[index]
            if time >= cue.start, time < cue.end {
                result.append(cue)
            }
            index -= 1
        }
        return result.sorted { $0.start < $1.start }
    }

    public static func activeTexts(in cues: [SubtitleCue], at time: TimeInterval) -> [String] {
        activeCues(in: cues, at: time).map(\.text)
    }
}
