import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 转发 URLSession 下载回调（非隔离，回调里只做数据搬运，状态变更交回 actor）。
final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var manager: DownloadManager?

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
        let resumeData = (error as NSError).userInfo[resumeKey] as? Data
        let manager = self.manager
        Task { await manager?.handleError(id: id, message: error.localizedDescription, resumeData: resumeData) }
    }
}

/// 下载管理器：前台 URLSession + 断点续传（resumeData）+ JSON 持久化。
/// 说明：v1 使用前台会话；切后台/锁屏时下载会被系统挂起（M6 后续可切 background session）。
public actor DownloadManager {
    public static let shared = DownloadManager()

    private let store: DownloadStore
    private var records: [String: DownloadRecord] = [:]
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var resumeData: [String: Data] = [:]
    private var continuations: [UUID: AsyncStream<[DownloadRecord]>.Continuation] = [:]
    private var session: URLSession!
    private let delegate: DownloadSessionDelegate

    public init(store: DownloadStore = DownloadStore()) {
        self.store = store
        self.delegate = DownloadSessionDelegate()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        try? FileManager.default.createDirectory(
            at: store.downloadsDirectory,
            withIntermediateDirectories: true
        )

        var restoredRecords: [String: DownloadRecord] = [:]
        for record in store.load() {
            var restored = record
            if restored.state == .downloading || restored.state == .queued {
                restored.state = .paused
            }
            restoredRecords[restored.id] = restored
        }
        self.records = restoredRecords
        self.delegate.manager = self
    }

    // MARK: - 查询

    public func snapshot() -> [DownloadRecord] {
        records.values.sorted { $0.updatedAt > $1.updatedAt }
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
        if let existing = records[fileID], existing.state == .completed { return }

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
        guard let data = resumeData[id] else {
            // 没有断点数据（例如 App 重启后）→ 明确失败，由用户重新添加
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
        task.resume()
        resumeData[id] = nil
        updateState(id: id, to: .downloading)
        emit()
    }

    public func cancel(id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        resumeData[id] = nil
        updateState(id: id, to: .cancelled)
        if let path = records[id]?.localPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        emit()
    }

    public func remove(id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        resumeData[id] = nil
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
        guard var record = records[id] else { return }
        if let data {
            resumeData[id] = data
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
