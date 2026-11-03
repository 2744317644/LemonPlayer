import XCTest
@testable import LemonSubtitle

final class SubtitleMatcherTests: XCTestCase {
    func testEpisodeExtraction() {
        XCTAssertEqual(SubtitleMatcher.episodeNumber(in: "Sousou no Frieren - 01 [1080p].mkv"), 1)
        XCTAssertEqual(SubtitleMatcher.episodeNumber(in: "Show.S02E12.1080p.mkv"), 12)
        XCTAssertEqual(SubtitleMatcher.episodeNumber(in: "进击的巨人 第05话.mkv"), 5)
        XCTAssertEqual(SubtitleMatcher.episodeNumber(in: "[Group] 动漫 - 12v2 [BDRip].mkv"), 12)
    }

    func testNormalizationRemovesNoise() {
        let base = SubtitleMatcher.normalizedBase("[Nekomoe kissaten] Sousou no Frieren - 01 [1080p][CHS].ass")
        XCTAssertFalse(base.contains("1080"))
        XCTAssertFalse(base.contains("chs"))
        XCTAssertTrue(base.contains("frieren"))
    }

    func testExactMatchScoresHighest() {
        let video = "[Nekomoe kissaten] Sousou no Frieren - 01 [1080p].mkv"
        let subs = [
            "[Nekomoe kissaten] Sousou no Frieren - 01 [1080p].chs.srt",
            "[Nekomoe kissaten] Sousou no Frieren - 01 [1080p].ass",
            "Unrelated.Show.01.srt"
        ]
        let result = SubtitleMatcher.candidates(videoName: video, subtitleNames: subs)
        XCTAssertEqual(result.first?.fileName, "[Nekomoe kissaten] Sousou no Frieren - 01 [1080p].ass")
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains { $0.fileName == "Unrelated.Show.01.srt" })
    }

    func testEpisodeMismatchExcluded() {
        let video = "Show - 01.mkv"
        let subs = ["Show - 02.srt", "Show - 01.srt"]
        let result = SubtitleMatcher.candidates(videoName: video, subtitleNames: subs)
        XCTAssertEqual(result.map(\.fileName), ["Show - 01.srt"])
    }

    func testLanguageDetection() {
        XCTAssertEqual(SubtitleMatcher.languageOf("ep01.chs.srt"), .chineseSimplified)
        XCTAssertEqual(SubtitleMatcher.languageOf("ep01.zh-tw.ass"), .chineseTraditional)
        XCTAssertEqual(SubtitleMatcher.languageOf("ep01.jpn.srt"), .japanese)
        XCTAssertEqual(SubtitleMatcher.languageOf("ep01.eng.vtt"), .english)
        XCTAssertEqual(SubtitleMatcher.languageOf("ep01.srt"), .unknown)
    }

    func testNonSubtitleFilesIgnored() {
        let result = SubtitleMatcher.candidates(videoName: "Show.mkv", subtitleNames: ["Show.mkv", "cover.jpg", "Show.srt"])
        XCTAssertEqual(result.map(\.fileName), ["Show.srt"])
    }
}
