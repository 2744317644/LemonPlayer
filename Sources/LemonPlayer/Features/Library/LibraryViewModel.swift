import Foundation
import Observation
import LemonGuangya
import LemonMedia
import LemonPersistence
import LemonPlayback

/// 媒体库：扫描网盘视频 → 文件名解析分组 → Bangumi 匹配 → 缓存与展示。
@MainActor
@Observable
final class LibraryViewModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case loaded
        case failed(String)
    }

    private(set) var series: [LibrarySeries] = []
    private(set) var recent: [PlaybackProgress] = []
    private(set) var phase: Phase = .idle
    private(set) var statusMessage: String?

    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let store = LibraryStore()
    @ObservationIgnored private let progressStore = PlaybackProgressStore()
    @ObservationIgnored private let matchCache = LibraryMatchCache()
    @ObservationIgnored private let bangumi = BangumiClient()
    @ObservationIgnored private let fileService: GuangyaFileService
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init(session: SessionStore) {
        self.session = session
        self.fileService = GuangyaFileService(identity: session.identity)
    }

    func loadCached() async {
        let cached = await store.load()
        if !cached.isEmpty {
            series = cached
            phase = .loaded
        }
        await loadRecent()
    }

    func loadRecent() async {
        recent = await progressStore.recent(limit: 12)
    }

    func scan() async {
        guard phase != .scanning else { return }
        phase = .scanning
        let task = Task { await self.performScan() }
        scanTask = task
        await task.value
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
    }

    private func performScan() async {
        statusMessage = "正在枚举网盘视频…"
        do {
            let token = try await session.validAccessToken()
            let files = try await fileService.listAllVideos(accessToken: token)
            if Task.isCancelled {
                phase = .idle
                statusMessage = nil
                return
            }
            statusMessage = "找到 \(files.count) 个视频，正在匹配…"

            let inputs = files.map {
                VideoFile(id: $0.id, name: $0.name, parentID: $0.parentID)
            }
            let client = bangumi
            let tmdbKey = UserDefaults.standard.string(forKey: "lemonplayer.tmdb.key") ?? ""
            let tmdb = TMDBClient(apiKey: tmdbKey)
            let cache = matchCache
            let (progressStream, progressContinuation) = AsyncStream<(Int, Int)>.makeStream()
            let progressTask = Task { [weak self] in
                for await (done, total) in progressStream {
                    self?.statusMessage = "匹配中 \(done)/\(total)…"
                }
            }

            let built = await LibraryScraper.build(
                files: inputs,
                onProgress: { done, total in progressContinuation.yield((done, total)) }
            ) { title in
                // 命中缓存直接返回（含"未命中"缓存），减少 Bangumi 请求
                if let cached = await cache.lookup(for: title) {
                    switch cached {
                    case .match(let match):
                        return match
                    case .miss:
                        return nil
                    }
                }

                if let subject = try? await client.searchSubjects(keyword: title, limit: 3).first {
                    let match = LibraryMatch(
                        bangumiID: subject.id,
                        title: subject.displayName,
                        coverURL: subject.coverURL?.absoluteString,
                        year: Int(String(subject.date?.prefix(4) ?? "")),
                        score: subject.rating?.score
                    )
                    await cache.store(match, for: title)
                    return match
                }

                // Bangumi 未命中：用 TMDB 兜底（需用户在设置中填 Key）
                if tmdb.isConfigured,
                   let result = try? await tmdb.search(title).first {
                    let match = LibraryMatch(
                        bangumiID: nil,
                        title: result.displayTitle,
                        coverURL: result.posterURL?.absoluteString,
                        year: result.year,
                        score: result.voteAverage
                    )
                    await cache.store(match, for: title)
                    return match
                }

                await cache.store(nil, for: title)
                return nil
            }
            progressContinuation.finish()
            progressTask.cancel()

            if Task.isCancelled {
                phase = .idle
                statusMessage = nil
                return
            }

            series = built
            await store.save(built)
            phase = .loaded
            statusMessage = nil
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func clearCache() async {
        await store.clear()
        series = []
        phase = .idle
    }
}
