import XCTest
@testable import LemonSubtitle

final class LemonSubtitleTests: XCTestCase {
    func testSupportedExtensions() {
        XCTAssertTrue(LemonSubtitle.supportedExtensions.contains("srt"))
        XCTAssertTrue(LemonSubtitle.supportedExtensions.contains("ass"))
        XCTAssertTrue(LemonSubtitle.supportedExtensions.contains("vtt"))
    }
}
