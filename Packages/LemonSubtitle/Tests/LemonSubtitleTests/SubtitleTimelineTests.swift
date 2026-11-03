import XCTest
@testable import LemonSubtitle

final class SubtitleTimelineTests: XCTestCase {
    private var cues: [SubtitleCue] {
        [
            SubtitleCue(id: 0, start: 1, end: 3, text: "A"),
            SubtitleCue(id: 1, start: 3, end: 5, text: "B"),
            SubtitleCue(id: 2, start: 5, end: 7, text: "C"),
            SubtitleCue(id: 3, start: 20, end: 22, text: "D")
        ]
    }

    func testExactBoundaries() {
        XCTAssertEqual(SubtitleTimeline.activeTexts(in: cues, at: 0.5), [])
        XCTAssertEqual(SubtitleTimeline.activeTexts(in: cues, at: 1), ["A"])
        XCTAssertEqual(SubtitleTimeline.activeTexts(in: cues, at: 2.99), ["A"])
        XCTAssertEqual(SubtitleTimeline.activeTexts(in: cues, at: 3), ["B"])
        XCTAssertEqual(SubtitleTimeline.activeTexts(in: cues, at: 21), ["D"])
    }

    func testGapReturnsEmpty() {
        XCTAssertEqual(SubtitleTimeline.activeTexts(in: cues, at: 10), [])
    }

    func testOverlappingCues() {
        let overlap = [
            SubtitleCue(id: 0, start: 1, end: 4, text: "主"),
            SubtitleCue(id: 1, start: 2, end: 3, text: "副"),
            SubtitleCue(id: 2, start: 5, end: 6, text: "后")
        ]
        XCTAssertEqual(SubtitleTimeline.activeTexts(in: overlap, at: 2.5), ["主", "副"])
    }

    func testEmptyCues() {
        XCTAssertEqual(SubtitleTimeline.activeTexts(in: [], at: 1), [])
    }
}
