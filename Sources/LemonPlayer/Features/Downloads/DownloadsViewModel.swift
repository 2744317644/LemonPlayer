import Foundation
import Observation
import LemonDownloads

/// 下载页状态：订阅 DownloadManager 的进度流。
@MainActor
@Observable
final class DownloadsViewModel {
    private(set) var records: [DownloadRecord] = []
    private(set) var totalDownloadedBytes: Int64 = 0

    @ObservationIgnored private let manager = DownloadManager.shared
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    func start() async {
        records = await manager.snapshot()
        updateTotals()
        streamTask?.cancel()
        let manager = self.manager
        streamTask = Task { [weak self] in
            for await list in await manager.updates() {
                guard let self else { return }
                self.records = list
                self.updateTotals()
            }
        }
    }

    func pause(_ record: DownloadRecord) {
        Task { await manager.pause(id: record.id) }
    }

    func resume(_ record: DownloadRecord) {
        Task { await manager.resume(id: record.id) }
    }

    func cancel(_ record: DownloadRecord) {
        Task { await manager.cancel(id: record.id) }
    }

    func remove(_ record: DownloadRecord) {
        Task { await manager.remove(id: record.id) }
    }

    func remove(at offsets: IndexSet) {
        let targets = offsets.map { records[$0] }
        for record in targets {
            Task { await manager.remove(id: record.id) }
        }
    }

    private func updateTotals() {
        totalDownloadedBytes = records.reduce(0) { $0 + $1.downloadedBytes }
    }
}

extension DownloadRecord {
    var stateText: String {
        switch state {
        case .queued: return "排队中"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}
