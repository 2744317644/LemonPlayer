import XCTest
@testable import LemonCore

final class LemonCoreTests: XCTestCase {
    func testVersionIsNotEmpty() {
        XCTAssertFalse(LemonCore.version.isEmpty)
    }

    func testBuildIsNotEmpty() {
        XCTAssertFalse(LemonCore.build.isEmpty)
    }
}
