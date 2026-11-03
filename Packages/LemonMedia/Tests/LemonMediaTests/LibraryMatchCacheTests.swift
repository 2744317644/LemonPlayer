import XCTest
@testable import LemonMedia

final class LibraryMatchCacheTests: XCTestCase {
    private func makeCache(configuration: LibraryMatchCache.Configuration = .init()) -> LibraryMatchCache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("match-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LibraryMatchCache(directory: directory, configuration: configuration)
    }

    private func sampleMatch() -> LibraryMatch {
        LibraryMatch(bangumiID: 1, title: "葬送的芙莉莲", coverURL: "https://img/1.jpg", year: 2023, score: 8.9)
    }

    func testNormalizationCollapsesCaseSpacesUnderscores() {
        XCTAssertEqual(LibraryMatchCache.normalize("葬送的 芙莉莲_Frieren"), LibraryMatchCache.normalize("葬送的芙莉莲_frieren"))
        XCTAssertEqual(LibraryMatchCache.normalize("A B"), "ab")
    }

    func testStoresAndReadsMatch() async {
        let cache = makeCache()
        await cache.store(sampleMatch(), for: "葬送的芙莉莲")
        let result = await cache.lookup(for: " 葬送的_芙莉莲 ")
        guard case .match(let match)? = result else {
            return XCTFail("应命中缓存")
        }
        XCTAssertEqual(match.bangumiID, 1)
        XCTAssertEqual(match.year, 2023)
    }

    func testMissIsCachedSeparately() async {
        let cache = makeCache()
        await cache.store(nil, for: "不存在的番")
        let result = await cache.lookup(for: "不存在的番")
        guard case .miss? = result else {
            return XCTFail("未命中应返回 .miss")
        }
    }

    func testSuccessExpiresAfterTTL() async {
        let cache = makeCache(configuration: .init(successTTL: 60, missTTL: 60))
        let start = Date()
        await cache.store(sampleMatch(), for: "标题", now: start)

        let within = await cache.lookup(for: "标题", now: start.addingTimeInterval(30))
        XCTAssertNotNil(within)

        let expired = await cache.lookup(for: "标题", now: start.addingTimeInterval(120))
        XCTAssertNil(expired)
    }

    func testMissUsesItsOwnTTL() async {
        let cache = makeCache(configuration: .init(successTTL: 3600, missTTL: 60))
        let start = Date()
        await cache.store(nil, for: "标题", now: start)

        let within = await cache.lookup(for: "标题", now: start.addingTimeInterval(30))
        guard case .miss? = within else { return XCTFail("应仍是未命中缓存") }

        let expired = await cache.lookup(for: "标题", now: start.addingTimeInterval(120))
        XCTAssertNil(expired)
    }

    func testTrimsWhenExceedingMaxEntries() async {
        let cache = makeCache(configuration: .init(maxEntries: 10))
        for index in 0..<20 {
            await cache.store(sampleMatch(), for: "标题\(index)", now: Date().addingTimeInterval(Double(index)))
        }
        let count = await cache.count()
        XCTAssertLessThanOrEqual(count, 10)
    }
}
