import XCTest
@testable import LemonSubtitle

final class SubtitleSerializerTests: XCTestCase {
    func testTimestampFormatting() {
        XCTAssertEqual(SubtitleSerializer.timestamp(0), "00:00:00,000")
        XCTAssertEqual(SubtitleSerializer.timestamp(1.5), "00:00:01,500")
        XCTAssertEqual(SubtitleSerializer.timestamp(3661.25), "01:01:01,250")
        XCTAssertEqual(SubtitleSerializer.timestamp(-3), "00:00:00,000")
    }

    func testSRTRoundTripWithOffset() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,000
        第一句

        2
        00:00:04,000 --> 00:00:06,000
        第二句
        """
        let document = try SubtitleParser.parse(data: Data(srt.utf8), fileExtension: "srt")
        let shifted = SubtitleSerializer.srt(from: document.cues, offset: 1.5)
        let reparsed = try SubtitleParser.parse(data: Data(shifted.utf8), fileExtension: "srt")

        XCTAssertEqual(reparsed.cues.count, 2)
        XCTAssertEqual(reparsed.cues[0].start, 2.5, accuracy: 0.001)
        XCTAssertEqual(reparsed.cues[1].end, 7.5, accuracy: 0.001)
        XCTAssertEqual(reparsed.cues[0].text, "第一句")
    }

    func testNegativeOffsetClampsToZero() throws {
        let cues = [SubtitleCue(id: 0, start: 1, end: 2, text: "x")]
        let output = SubtitleSerializer.srt(from: cues, offset: -10)
        let reparsed = try SubtitleParser.parse(data: Data(output.utf8), fileExtension: "srt")
        XCTAssertEqual(reparsed.cues[0].start, 0, accuracy: 0.001)
    }

    func testASSShiftPreservesTextAndTags() {
        let ass = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\\pos(100,50)}你好
        Dialogue: 0,0:00:05.00,0:00:07.00,Default,,0,0,0,,第二句
        """
        let shifted = ASSSubtitleShifter.shift(ass, after: 2.0)
        XCTAssertTrue(shifted.contains("0:00:03.00,0:00:05.00"))
        XCTAssertTrue(shifted.contains("{\\pos(100,50)}你好"))
        XCTAssertTrue(shifted.contains("第二句"))
    }
}
