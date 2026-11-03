import XCTest
@testable import LemonMedia

final class LibraryScraperTests: XCTestCase {
    private func file(_ id: String, _ name: String, parent: String = "dir") -> VideoFile {
        VideoFile(id: id, name: name, parentID: parent)
    }

    func testGroupingByTitleAndSeason() {
        let files = [
            file("1", "[Group] Frieren - 01 [1080p].mkv"),
            file("2", "[Group] Frieren - 02 [1080p].mkv"),
            file("3", "[Group] Frieren S02E01 [1080p].mkv"),
            file("4", "[Group] Other Show - 01.mkv")
        ]
        let groups = LibraryScraper.group(files)
        XCTAssertEqual(groups.count, 3)
        let frieren = groups.first { $0.title.contains("Frieren") && $0.season == nil }
        XCTAssertEqual(frieren?.files.count, 2)
    }

    func testBuildSortsEpisodesAndUsesMatch() async {
        let files = [
            file("3", "Show - 03.mkv"),
            file("1", "Show - 01.mkv"),
            file("2", "Show - 02.mkv")
        ]
        let series = await LibraryScraper.build(files: files) { title in
            LibraryMatch(bangumiID: 42, title: "匹配标题", coverURL: "https://img", year: 2024, score: 8.1)
        }

        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].bangumiID, 42)
        XCTAssertEqual(series[0].title, "匹配标题")
        XCTAssertEqual(series[0].id, "42")
        XCTAssertEqual(series[0].episodes.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(series[0].episodes.map(\.episode), [1, 2, 3])
    }

    func testBuildFallsBackWhenNoMatch() async {
        let files = [file("1", "Mushoku Tensei - 01.mkv")]
        let series = await LibraryScraper.build(files: files) { _ in nil }
        XCTAssertEqual(series.count, 1)
        XCTAssertNil(series[0].bangumiID)
        XCTAssertEqual(series[0].episodes.count, 1)
    }

    func testEmptyInput() async {
        let series = await LibraryScraper.build(files: []) { _ in nil }
        XCTAssertTrue(series.isEmpty)
    }
}
