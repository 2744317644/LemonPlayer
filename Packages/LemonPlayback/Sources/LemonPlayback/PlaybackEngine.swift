import Foundation

/// 播放器状态机（与内核无关的高层状态）。
public enum PlaybackState: Equatable, Sendable {
    case idle
    case preparing
    case ready
    case playing
    case paused
    case buffering(progress: Double)
    case ended
    case failed(String)

    public var isActive: Bool {
        switch self {
        case .ready, .playing, .paused, .buffering: return true
        case .idle, .preparing, .ended, .failed: return false
        }
    }
}

/// 可播放源（直链 + 请求头 + 标题）。
public struct PlaybackSource: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]
    public let title: String

    public init(url: URL, headers: [String: String] = [:], title: String = "") {
        self.url = url
        self.headers = headers
        self.title = title
    }
}

public enum TrackKind: String, Sendable, Equatable {
    case audio
    case subtitle
}

/// 轨道信息（音轨 / 字幕轨）。
public struct PlaybackTrack: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let name: String
    public let language: String?
    public let kind: TrackKind
    public let isExternal: Bool

    public init(id: Int32, name: String, language: String?, kind: TrackKind, isExternal: Bool = false) {
        self.id = id
        self.name = name
        self.language = language
        self.kind = kind
        self.isExternal = isExternal
    }
}

/// 播放引擎抽象。VLCKit / MPVKit / AVPlayer 各自实现，App 层只依赖本协议。
@MainActor
public protocol PlaybackEngine: AnyObject {
    var state: PlaybackState { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var rate: Float { get set }
    var audioTracks: [PlaybackTrack] { get }
    var subtitleTracks: [PlaybackTrack] { get }

    func load(_ source: PlaybackSource) async throws
    func play()
    func pause()
    func stop()
    func seek(to time: TimeInterval) async
    func selectAudioTrack(id: Int32)
    func selectSubtitleTrack(id: Int32?) 
    func addExternalSubtitle(url: URL, encoding: String.Encoding?) async throws
    func removeExternalSubtitles()
}

/// 播放错误（对外统一）。
public enum PlaybackError: Error, Equatable, Sendable {
    case unsupportedFormat
    case sourceExpired
    case trackUnavailable
    case network(String)
    case engine(String)

    public var localizedDescription: String {
        switch self {
        case .unsupportedFormat: return "该视频格式暂不支持"
        case .sourceExpired: return "播放地址已过期，正在重新获取"
        case .trackUnavailable: return "该轨道不可用"
        case .network(let message): return "网络错误：\(message)"
        case .engine(let message): return "播放器错误：\(message)"
        }
    }
}
