import Foundation
import Observation
import LemonGuangya

/// 目录浏览状态机：分页、面包屑、排序、错误重试。
@MainActor
@Observable
final class BrowseViewModel {
    struct Crumb: Identifiable, Equatable {
        let id: String
        let name: String
    }

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case timeDescending
        case timeAscending
        case nameAscending
        case nameDescending

        var id: String { rawValue }

        var title: String {
            switch self {
            case .timeDescending: return "最新优先"
            case .timeAscending: return "最早优先"
            case .nameAscending: return "名称 A→Z"
            case .nameDescending: return "名称 Z→A"
            }
        }

        /// 依据 `docs/api/GUANGYA_API.md` §3.2：orderBy 3 = 时间，1 = 名称（名称排序待真机验证）。
        var orderBy: Int {
            switch self {
            case .timeDescending, .timeAscending: return 3
            case .nameAscending, .nameDescending: return 1
            }
        }

        /// 0 = 升序，1 = 降序。
        var sortType: Int {
            switch self {
            case .timeDescending, .nameDescending: return 1
            case .timeAscending, .nameAscending: return 0
            }
        }
    }

    private(set) var items: [GuangyaFile] = []
    private(set) var phase: Phase = .idle
    private(set) var crumbs: [Crumb] = [Crumb(id: "", name: "根目录")]
    private(set) var sort: SortOption = .timeDescending
    private(set) var hasMore = false
    private(set) var isLoadingMore = false

    private let session: SessionStore
    private let service: GuangyaFileService
    private let pageSize = 100
    private var page = 0

    init(session: SessionStore) {
        self.session = session
        self.service = GuangyaFileService(identity: session.identity)
    }

    var currentFolderID: String { crumbs.last?.id ?? "" }
    var currentFolderName: String { crumbs.last?.name ?? "网盘" }
    var canGoUp: Bool { crumbs.count > 1 }

    func start() async {
        guard items.isEmpty, phase == .idle else { return }
        await reload()
    }

    func reload() async {
        phase = .loading
        page = 0
        do {
            let result = try await fetch(page: 0)
            items = result.items
            hasMore = result.hasMore(pageSize: pageSize, accumulated: result.items.count)
            phase = .loaded
        } catch {
            phase = .failed(message(for: error))
        }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = page + 1
        do {
            let result = try await fetch(page: nextPage)
            page = nextPage
            items.append(contentsOf: result.items)
            hasMore = result.hasMore(pageSize: pageSize, accumulated: items.count)
        } catch {
            // 加载更多失败不打断已加载内容，仅停止继续加载
            hasMore = false
        }
    }

    func changeSort(_ option: SortOption) async {
        guard option != sort else { return }
        sort = option
        await reload()
    }

    func enter(_ folder: GuangyaFile) async {
        guard folder.isFolder else { return }
        crumbs.append(Crumb(id: folder.id, name: folder.name))
        items = []
        await reload()
    }

    func goUp() async {
        guard canGoUp else { return }
        crumbs.removeLast()
        items = []
        await reload()
    }

    func jump(to crumb: Crumb) async {
        guard let index = crumbs.firstIndex(of: crumb), index != crumbs.count - 1 else { return }
        crumbs.removeSubrange((index + 1)...)
        items = []
        await reload()
    }

    private func fetch(page: Int) async throws -> FileListPage {
        let token = try await session.validAccessToken()
        return try await service.listFiles(
            parentID: currentFolderID,
            page: page,
            pageSize: pageSize,
            orderBy: sort.orderBy,
            sortType: sort.sortType,
            accessToken: token
        )
    }

    private func message(for error: Error) -> String {
        if let error = error as? GuangyaError {
            return error.localizedDescription
        }
        return error.localizedDescription
    }
}
