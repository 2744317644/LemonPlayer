import Foundation

/// 下载任务状态机（与 URLSession 解耦，便于测试）。
public enum DownloadState: String, Codable, Sendable, Equatable {
    case queued
    case downloading
    case paused
    case completed
    case failed
    case cancelled
}

public struct DownloadRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String              // fileID
    public let fileName: String
    public let parentID: String
    public var state: DownloadState
    public var totalBytes: Int64
    public var downloadedBytes: Int64
    public var localPath: String?
    public var updatedAt: Date
    public var errorMessage: String?

    public init(
        id: String,
        fileName: String,
        parentID: String,
        state: DownloadState = .queued,
        totalBytes: Int64 = 0,
        downloadedBytes: Int64 = 0,
        localPath: String? = nil,
        updatedAt: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.parentID = parentID
        self.state = state
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.localPath = localPath
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
    }

    public var progressFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(downloadedBytes) / Double(totalBytes), 0), 1)
    }

    public var isActive: Bool {
        state == .downloading || state == .queued
    }
}

/// 合法状态迁移规则。非法迁移直接拒绝（幂等返回原状态）。
public enum DownloadStateMachine {
    public static func canTransition(from: DownloadState, to: DownloadState) -> Bool {
        switch (from, to) {
        case (.queued, .downloading), (.queued, .cancelled), (.queued, .paused),
             (.downloading, .paused), (.downloading, .completed),
             (.downloading, .failed), (.downloading, .cancelled),
             (.downloading, .queued),
             (.paused, .downloading), (.paused, .cancelled), (.paused, .queued),
             (.failed, .queued), (.failed, .cancelled),
             (.cancelled, .queued):
            return true
        default:
            return false
        }
    }

    public static func apply(_ record: DownloadRecord, to state: DownloadState) -> DownloadRecord {
        guard canTransition(from: record.state, to: state) else { return record }
        var updated = record
        updated.state = state
        updated.updatedAt = Date()
        if state == .completed {
            updated.downloadedBytes = updated.totalBytes
        }
        if state == .queued {
            updated.errorMessage = nil
        }
        return updated
    }
}
