import XCTest
@testable import LemonMedia

final class MediaNameParserTests: XCTestCase {
    func testAnimeWithGroupAndResolution() {
        let parsed = MediaNameParser.parse("[Nekomoe kissaten] Sousou no Frieren - 01 [1080p][CHS].mkv")
        XCTAssertEqual(parsed.episode, 1)
        XCTAssertEqual(parsed.resolution, "1080p")
        XCTAssertTrue(parsed.title.localizedCaseInsensitiveContains("frieren"))
        XCTAssertFalse(parsed.isMovie)
    }

    func testSeasonEpisodeNaming() {
        let parsed = MediaNameParser.parse("Shingeki.no.Kyojin.S02E05.1080p.WEB-DL.mkv")
        XCTAssertEqual(parsed.season, 2)
        XCTAssertEqual(parsed.episode, 5)
        XCTAssertEqual(parsed.resolution, "1080p")
    }

    func testChineseSeasonAndEpisode() {
        let parsed = MediaNameParser.parse("进击的巨人 第二季 第05话 [1080p].mkv")
        XCTAssertEqual(parsed.season, 2)
        XCTAssertEqual(parsed.episode, 5)
        XCTAssertTrue(parsed.title.contains("进击的巨人"))
    }

    func testMovieWithYear() {
        let parsed = MediaNameParser.parse("你的名字 (2016) [1080p].mkv")
        XCTAssertEqual(parsed.year, 2016)
        XCTAssertNil(parsed.episode)
        XCTAssertTrue(parsed.isMovie)
        XCTAssertTrue(parsed.title.contains("你的名字"))
    }

    func testEpisodeOnlyDash() {
        let parsed = MediaNameParser.parse("Mushoku Tensei - 12 [BDRip].mkv")
        XCTAssertEqual(parsed.episode, 12)
        XCTAssertNil(parsed.season)
    }
}
