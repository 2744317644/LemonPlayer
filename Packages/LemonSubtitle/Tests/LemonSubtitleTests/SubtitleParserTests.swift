import XCTest
@testable import LemonSubtitle

final class SubtitleParserTests: XCTestCase {
    func testSRTParsing() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,500
        第一行字幕
        第二行

        2
        00:00:04,000 --> 00:00:06,000
        Hello <i>world</i>

        """
        let document = try SubtitleParser.parse(data: Data(srt.utf8), fileExtension: "srt")
        XCTAssertEqual(document.format, .srt)
        XCTAssertEqual(document.cues.count, 2)
        XCTAssertEqual(document.cues[0].start, 1.0, accuracy: 0.001)
        XCTAssertEqual(document.cues[0].end, 3.5, accuracy: 0.001)
        XCTAssertEqual(document.cues[0].text, "第一行字幕\n第二行")
        XCTAssertEqual(document.cues[1].text, "Hello <i>world</i>")
    }

    func testSRTTolerantWithoutIndexesAndWithDotMilliseconds() throws {
        let srt = """
        00:00:01.000 --> 00:00:02.000
        没有序号

        00:00:03.000 --> 00:00:04.000
        第二条
        """
        let document = try SubtitleParser.parse(data: Data(srt.utf8), fileExtension: "srt")
        XCTAssertEqual(document.cues.count, 2)
        XCTAssertEqual(document.cues[1].start, 3.0, accuracy: 0.001)
    }

    func testWebVTTParsingWithHeaderAndSettings() throws {
        let vtt = """
        WEBVTT

        00:01.000 --> 00:02.500 align:start position:0%
        中文字幕

        00:03.000 --> 00:04.000
        second line
        """
        let document = try SubtitleParser.parse(data: Data(vtt.utf8), fileExtension: "vtt")
        XCTAssertEqual(document.format, .vtt)
        XCTAssertEqual(document.cues.count, 2)
        XCTAssertEqual(document.cues[0].start, 1.0, accuracy: 0.001)
        XCTAssertEqual(document.cues[0].text, "中文字幕")
    }

    func testASSParsingAndTagStripping() throws {
        let ass = """
        [Script Info]
        Title: test

        [V4+ Styles]
        Format: Name, Fontname

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,{\\pos(10,20)}你好，世界
        Dialogue: 0,0:00:04.00,0:00:06.00,Default,,0,0,0,,第一行\\N第二行
        """
        let document = try SubtitleParser.parse(data: Data(ass.utf8), fileExtension: "ass")
        XCTAssertEqual(document.format, .ass)
        XCTAssertEqual(document.cues.count, 2)
        XCTAssertEqual(document.cues[0].text, "你好，世界")
        XCTAssertEqual(document.cues[1].text, "第一行\n第二行")
    }

    func testFormatDetection() {
        XCTAssertEqual(SubtitleParser.detectFormat(fileExtension: "SRT", text: ""), .srt)
        XCTAssertEqual(SubtitleParser.detectFormat(fileExtension: nil, text: "WEBVTT\n\n00:01.000 --> 00:02.000\nx"), .vtt)
        XCTAssertEqual(SubtitleParser.detectFormat(fileExtension: nil, text: "[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,x"), .ass)
        XCTAssertEqual(SubtitleParser.detectFormat(fileExtension: "txt", text: "plain"), .unknown)
    }

    func testActiveCue() {
        let cue = SubtitleCue(id: 0, start: 10, end: 12, text: "x")
        XCTAssertFalse(cue.isActive(at: 9.9))
        XCTAssertTrue(cue.isActive(at: 10))
        XCTAssertTrue(cue.isActive(at: 11.9))
        XCTAssertFalse(cue.isActive(at: 12))
    }
}
