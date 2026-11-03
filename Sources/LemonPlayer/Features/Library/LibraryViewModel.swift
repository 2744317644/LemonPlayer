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
    @ObservationIgnored private let bangumi = BangumiClient()
    @ObservationIgnored private let fileService: GuangyaFileService

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
        statusMessage = "正在枚举网盘视频…"
        do {
            let token = try await session.validAccessToken()
            let files = try await fileService.listAllVideos(accessToken: token)
            statusMessage = "找到 \(files.count) 个视频，正在匹配 Bangumi…"

            let inputs = files.map {
                VideoFile(id: $0.id, name: $0.name, parentID: $0.parentID)
            }
            let client = bangumi
            let tmdbKey = UserDefaults.standard.string(forKey: "lemonplayer.tmdb.key") ?? ""
            let tmdb = TMDBClient(apiKey: tmdbKey)
            let built = await LibraryScraper.build(files: inputs) { title in
                if let subject = try? await client.searchSubjects(keyword: title, limit: 3).first {
                    return LibraryMatch(
                        bangumiID: subject.id,
                        title: subject.displayName,
                        coverURL: subject.coverURL?.absoluteString,
                        year: Int(String(subject.date?.prefix(4) ?? "")),
                        score: subject.rating?.score
                    )
                }
                // Bangumi 未命中：用 TMDB 兜底（需用户在设置中填 Key）
                if tmdb.isConfigured,
                   let result = try? await tmdb.search(title).first {
                    return LibraryMatch(
                        bangumiID: nil,
                        title: result.displayTitle,
                        coverURL: result.posterURL?.absoluteString,
                        year: result.year,
                        score: result.voteAverage
                    )
                }
                return nil
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
