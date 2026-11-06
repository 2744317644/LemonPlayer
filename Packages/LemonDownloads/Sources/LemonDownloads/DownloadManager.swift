import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 转发 URLSession 下载回调（非隔离，回调里只做数据搬运，状态变更交回 actor）。
final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var manager: DownloadManager?

    #if os(iOS)
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }
        BackgroundSessionEvents.shared.finish(identifier: identifier)
    }
    #endif

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadTask.taskDescription else { return }
        let manager = self.manager
        Task { await manager?.handleProgress(id: id, written: totalBytesWritten, total: totalBytesExpectedToWrite) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        let incoming = FileManager.default.temporaryDirectory
            .appendingPathComponent("lemon-download-\(UUID().uuidString)")
        try? FileManager.default.moveItem(at: location, to: incoming)
        let manager = self.manager
        Task { await manager?.handleFinish(id: id, temporaryURL: incoming) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        #if canImport(Darwin)
        let resumeKey = NSURLSessionDownloadTaskResumeData
        #else
        let resumeKey = "NSURLSessionDownloadTaskResumeData"
        #endif
        let data = (error as NSError).userInfo[resumeKey] as? Data
        let manager = self.manager
        Task {
            await manager?.handleError(id: id, message: error.localizedDescription, resumeData: data)
        }
    }
}

/// 下载管理器：后台 URLSession（iOS）+ 断点续传（resumeData 持久化）+ JSON 持久化。
/// iOS 使用 background session，App 切后台/锁屏时下载继续；被系统终止后重启可恢复任务。
public actor DownloadManager {
    public static let shared = DownloadManager()
    public static let sessionIdentifier = "com.lemonplayer.downloads.background"

    private let store: DownloadStore
    private var records: [String: DownloadRecord] = [:]
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var resumeData: [String: Data] = [:]
    /// 用户主动取消的任务：忽略随后到达的 resumeData 回调，避免状态被改回 paused。
    private var cancelledIDs: Set<String> = []
    private var continuations: [UUID: AsyncStream<[DownloadRecord]>.Continuation] = [:]
    private var session: URLSession!
    private let delegate: DownloadSessionDelegate

    public init(store: DownloadStore = DownloadStore()) {
        self.store = store
        self.delegate = DownloadSessionDelegate()

        #if os(iOS)
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        #else
        let configuration = URLSessionConfiguration.default
        #endif
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 86_400

        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        try? FileManager.default.createDirectory(
            at: store.downloadsDirectory,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: store.resumeDataDirectory,
            withIntermediateDirectories: true
        )

        var restoredRecords: [String: DownloadRecord] = [:]
        var restoredResumeData: [String: Data] = [:]
        for record in store.load() {
            var restored = record
            if restored.state == .downloading || restored.state == .queued {
                restored.state = .paused
            }
            restoredRecords[restored.id] = restored
            if let data = store.resumeData(id: restored.id) {
                restoredResumeData[restored.id] = data
            }
        }
        self.records = restoredRecords
        self.resumeData = restoredResumeData
        self.delegate.manager = self
    }

    // MARK: - 查询

    public func snapshot() -> [DownloadRecord] {
        records.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func totalDownloadedBytes() -> Int64 {
        records.values.reduce(0) { $0 + $1.downloadedBytes }
    }

    public func completedCount() -> Int {
        records.values.filter { $0.state == .completed }.count
    }

    /// 清空全部任务与本地文件。
    public func removeAll() {
        for id in records.keys {
            tasks[id]?.cancel()
            tasks[id] = nil
            store.removeResumeData(id: id)
            if let path = records[id]?.localPath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        records.removeAll()
        resumeData.removeAll()
        cancelledIDs.removeAll()
        persist()
        emit()
    }

    /// 超过容量上限时按"最久未播放"清理已完成任务（只删已下载文件，不动进行中的任务）。
    public func enforceStorageLimit(maxBytes: Int64) {
        guard maxBytes > 0 else { return }
        var total = totalDownloadedBytes()
        guard total > maxBytes else { return }

        let completed = records.values
            .filter { $0.state == .completed }
            .sorted { $0.updatedAt < $1.updatedAt }

        for record in completed {
            guard total > maxBytes else { break }
            if let path = record.localPath {
                try? FileManager.default.removeItem(atPath: path)
            }
            total -= record.downloadedBytes
            records[record.id] = nil
        }
        persist()
        emit()
    }

    public func localURL(for fileID: String) -> URL? {
        guard let record = records[fileID], record.state == .completed,
              let path = record.localPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    public func updates() -> AsyncStream<[DownloadRecord]> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(snapshot())
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    // MARK: - 任务控制

    public func enqueue(
        fileID: String,
        fileName: String,
        parentID: String,
        url: URL,
        headers: [String: String]
    ) async {
        if let existing = records[fileID] {
            switch existing.state {
            case .completed, .downloading, .paused:
                return // 已完成/进行中/已暂停：不要重复起任务
            default:
                break
            }
        }
        cancelledIDs.remove(fileID)

        let record = DownloadRecord(
            id: fileID,
            fileName: fileName,
            parentID: parentID,
            state: .downloading,
            totalBytes: 0,
            downloadedBytes: 0,
            localPath: nil,
            updatedAt: Date(),
            errorMessage: nil
        )
        records[fileID] = record

        let request = makeRequest(url: url, headers: headers)
        let task = session.downloadTask(with: request)
        task.taskDescription = fileID
        tasks[fileID] = task
        task.resume()
        emit()
    }

    public func pause(id: String) {
        guard let task = tasks[id] else { return }
        tasks[id] = nil
        task.cancel()
        // 取消后 URLSession 会在 didCompleteWithError 里带上 resumeData（若可用）
        updateState(id: id, to: .paused)
        emit()
    }

    public func resume(id: String) async {
        guard let record = records[id], record.state == .paused || record.state == .failed else { return }
        cancelledIDs.remove(id)
        let data = resumeData[id] ?? store.resumeData(id: id)
        guard let data else {
            // 没有断点数据 → 明确失败，由用户重新添加
            guard var failed = records[id] else { return }
            failed.state = .failed
            failed.errorMessage = "断点信息已失效，请重新下载"
            failed.updatedAt = Date()
            records[id] = failed
            emit()
            return
        }
        let task = session.downloadTask(withResumeData: data)
        task.taskDescription = id
        tasks[id] = task
        resumeData[id] = data
        task.resume()
        updateState(id: id, to: .downloading)
        emit()
    }

    public func cancel(id: String) {
        cancelledIDs.insert(id)
        tasks[id]?.cancel()
        tasks[id] = nil
        resumeData[id] = nil
        store.removeResumeData(id: id)
        updateState(id: id, to: .cancelled)
        if let path = records[id]?.localPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        emit()
    }

    public func remove(id: String) {
        cancelledIDs.insert(id)
        tasks[id]?.cancel()
        tasks[id] = nil
        resumeData[id] = nil
        store.removeResumeData(id: id)
        if let path = records[id]?.localPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        records[id] = nil
        emit()
    }

    // MARK: - Delegate 回调

    func handleProgress(id: String, written: Int64, total: Int64) {
        guard var record = records[id] else { return }
        record.downloadedBytes = written
        if total > 0 { record.totalBytes = total }
        record.updatedAt = Date()
        records[id] = record
        emit()
    }

    func handleFinish(id: String, temporaryURL: URL) {
        cancelledIDs.remove(id)
        guard var record = records[id] else { return }
        let destination = store.downloadsDirectory
            .appendingPathComponent("\(id)-\(safeName(record.fileName))")
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            record.localPath = destination.path
            record.state = .completed
            record.downloadedBytes = record.totalBytes
            record.updatedAt = Date()
            records[id] = record
            resumeData[id] = nil
            store.removeResumeData(id: id)
            persist()
            emit()
        } catch {
            record.state = .failed
            record.errorMessage = error.localizedDescription
            records[id] = record
            persist()
            emit()
        }
    }

    func handleError(id: String, message: String, resumeData data: Data?) {
        // 用户主动取消：丢弃 URLSession 带回的 resumeData，保持 cancelled 状态
        if cancelledIDs.remove(id) != nil {
            store.removeResumeData(id: id)
            return
        }
        guard var record = records[id] else { return }
        if let data {
            resumeData[id] = data
            store.saveResumeData(data, id: id)
            record.state = .paused
        } else if record.state == .downloading {
            record.state = .failed
            record.errorMessage = message
        }
        record.updatedAt = Date()
        records[id] = record
        persist()
        emit()
    }

    // MARK: - 内部

    private func makeRequest(url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private func updateState(id: String, to state: DownloadState) {
        guard var record = records[id] else { return }
        record.state = state
        record.updatedAt = Date()
        records[id] = record
        persist()
    }

    private func storeResumeData(_ data: Data, id: String) {
        resumeData[id] = data
        store.saveResumeData(data, id: id)
        updateState(id: id, to: .paused)
        emit()
    }

    private func persist() {
        store.save(snapshot())
    }

    private func emit() {
        let current = snapshot()
        for continuation in continuations.values {
            continuation.yield(current)
        }
    }

    private func safeName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
