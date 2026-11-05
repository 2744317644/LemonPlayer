import XCTest
@testable import LemonMedia

final class TitleMatcherTests: XCTestCase {
    func testExtractSeason() {
        XCTAssertEqual(TitleMatcher.extractSeason("约会大作战 第三季"), 3)
        XCTAssertEqual(TitleMatcher.extractSeason("五等分の花嫁∬"), 2)
        XCTAssertEqual(TitleMatcher.extractSeason("からかい上手の高木さん②"), 2)
        XCTAssertEqual(TitleMatcher.extractSeason("Sousou no Frieren S02"), 2)
        XCTAssertEqual(TitleMatcher.extractSeason("孤独摇滚！"), nil)
    }

    func testPickBestPrefersCorrectSeason() {
        let candidates = [
            "约会大作战",
            "约会大作战 第二季",
            "约会大作战 第三季",
            "约会大作战 第四季"
        ]
        XCTAssertEqual(TitleMatcher.pickBest(title: "约会大作战 第三季", candidates: candidates), 2)
    }

    func testPickBestRejectsWrongSeasonWhenNoMatch() {
        let candidates = ["约会大作战", "约会大作战 第二季"]
        XCTAssertNil(TitleMatcher.pickBest(title: "约会大作战 第四季", candidates: candidates))
    }

    func testRomanizedSimilarity() {
        XCTAssertGreaterThan(
            TitleMatcher.similarity("Sousou no Frieren", "Sousou no Frieren"),
            0.99
        )
        XCTAssertLessThan(
            TitleMatcher.similarity("孤独摇滚！", "葬送的芙莉莲"),
            0.3
        )
    }

    func testNonAnimeTitles() {
        XCTAssertTrue(TitleMatcher.looksLikeNonAnime("Inori Minase 1st LIVE"))
        XCTAssertTrue(TitleMatcher.looksLikeNonAnime("歌曲欣赏"))
        XCTAssertFalse(TitleMatcher.looksLikeNonAnime("孤独摇滚！"))
    }
}
