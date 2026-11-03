import Foundation
import Observation
import LemonGuangya
import LemonMedia
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
    private(set) var phase: Phase = .idle
    private(set) var statusMessage: String?

    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let store = LibraryStore()
    @ObservationIgnored private let bangumi = BangumiClient()
    @ObservationIgnored private let fileService: GuangyaFileService

    init(session: SessionStore) {
        self.session = session
        self.fileService = GuangyaFileService(identity: session.identity)
    }

    func loadCached() async {
        let cached = await store.load()
        guard !cached.isEmpty else { return }
        series = cached
        phase = .loaded
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
            let built = await LibraryScraper.build(files: inputs) { title in
                guard let subject = try? await client.searchSubjects(keyword: title, limit: 3).first else {
                    return nil
                }
                return LibraryMatch(
                    bangumiID: subject.id,
                    title: subject.displayName,
                    coverURL: subject.coverURL?.absoluteString,
                    year: Int(String(subject.date?.prefix(4) ?? "")),
                    score: subject.rating?.score
                )
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
