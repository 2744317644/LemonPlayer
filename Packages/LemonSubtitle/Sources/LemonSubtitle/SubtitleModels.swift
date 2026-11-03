import Foundation

/// 统一字幕条目模型（SRT / WebVTT / ASS 解析后共享）。
public struct SubtitleCue: Identifiable, Equatable, Sendable {
    public let id: Int
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(id: Int, start: TimeInterval, end: TimeInterval, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }

    public func isActive(at time: TimeInterval) -> Bool {
        start <= time && time < end
    }
}

public enum SubtitleFormat: String, Sendable, CaseIterable {
    case srt
    case vtt
    case ass
    case unknown
}

public struct SubtitleDocument: Equatable, Sendable {
    public let format: SubtitleFormat
    public let cues: [SubtitleCue]
    public let encoding: String.Encoding

    public init(format: SubtitleFormat, cues: [SubtitleCue], encoding: String.Encoding) {
        self.format = format
        self.cues = cues
        self.encoding = encoding
    }
}
