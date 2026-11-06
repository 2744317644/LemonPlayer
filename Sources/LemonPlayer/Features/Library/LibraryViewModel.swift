import Foundation
import Observation
import LemonCore
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
        statusMessage = "正在枚举网盘目录…"
        do {
            let media = try await session.authorized { token in
                try await fileService.listAllMedia(accessToken: token)
            }
            if Task.isCancelled {
                phase = .idle
                statusMessage = nil
                return
            }

            // 还原目录树：以最底层非附属目录作为一部番剧（Fonts/OP/ED/SPs 等向上取父目录）
            let folderMap = Dictionary(
                media.folders.map {
                    ($0.id, LibraryFolderNode(id: $0.id, parentID: $0.parentID, name: $0.name))
                },
                uniquingKeysWith: { first, _ in first }
            )
            let videoFiles = media.files.filter { $0.kind == .video }
            statusMessage = "找到 \(videoFiles.count) 个视频（\(media.folders.count) 个目录），正在匹配…"

            let inputs = videoFiles.compactMap { file -> VideoFile? in
                // NCOP/NCED/OP/ED/SPs 等附属视频不算正片
                if SeriesFolderResolver.isNoiseFile(file.name) { return nil }
                if let parent = folderMap[file.parentID], SeriesFolderResolver.isNoiseFolder(parent.name) {
                    return nil
                }
                let resolved = SeriesFolderResolver.resolveSeriesFolder(
                    forFileParent: file.parentID,
                    folders: folderMap
                )
                return VideoFile(
                    id: file.id,
                    name: file.name,
                    parentID: file.parentID,
                    seriesFolderID: resolved?.id,
                    seriesFolderName: resolved?.name
                )
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

                // 罗马音/英文名兜底：先按清洗后的标题搜，再去掉标点搜一次
                if TitleMatcher.looksLikeNonAnime(title) {
                    await cache.store(nil, for: title)
                    return nil
                }
                let keywords = Self.searchKeywords(for: title)
                for keyword in keywords {
                    let subjects = (try? await client.searchSubjects(keyword: keyword, limit: 5)) ?? []
                    let names = subjects.map(\.displayName)
                    if let index = TitleMatcher.pickBest(title: title, candidates: names) {
                        let subject = subjects[index]
                        let episodeTitles = await Self.fetchEpisodeTitles(
                            client: client,
                            subjectID: subject.id
                        )
                        let match = LibraryMatch(
                            bangumiID: subject.id,
                            title: subject.displayName,
                            coverURL: subject.coverURL?.absoluteString,
                            year: Int(String(subject.date?.prefix(4) ?? "")),
                            score: subject.rating?.score,
                            episodeTitles: episodeTitles
                        )
                        await cache.store(match, for: title)
                        return match
                    }
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
            let lemon = LemonError.wrap(error)
            await DiagnosticsCenter.shared.log(lemon, category: "library")
            phase = .failed(lemon.errorDescription ?? lemon.diagnosticDescription)
        }
    }

    /// 拉取 Bangumi 分集标题（中文优先），失败返回空字典。
    nonisolated private static func fetchEpisodeTitles(
        client: BangumiClient,
        subjectID: Int
    ) async -> [Int: String] {
        guard let episodes = try? await client.episodes(subjectID: subjectID, type: 0) else {
            return [:]
        }
        var titles: [Int: String] = [:]
        for episode in episodes {
            // ep 是本季内集数（文件按本季编号），sort 是全系列连续集数
            let number = Int(episode.ep ?? episode.sort ?? 0)
            guard number > 0 else { continue }
            let name = (episode.nameCN?.isEmpty == false ? episode.nameCN : episode.name)
            if let name, !name.isEmpty {
                titles[number] = name
            }
        }
        return titles
    }

    /// 罗马音/英文名常见的标点差异：给出 2 个候选关键词。
    nonisolated private static func searchKeywords(for title: String) -> [String] {
        var keywords: [String] = []
        let cleaned = SeriesFolderResolver.cleanTitle(title)
        if !cleaned.isEmpty { keywords.append(cleaned) }

        let stripped = cleaned
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if !stripped.isEmpty, stripped != cleaned { keywords.append(stripped) }
        return keywords.isEmpty ? [title] : keywords
    }

    func clearCache() async {
        await store.clear()
        series = []
        phase = .idle
    }
}
