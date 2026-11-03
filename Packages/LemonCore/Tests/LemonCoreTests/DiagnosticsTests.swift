import XCTest
@testable import LemonCore

final class DiagnosticsTests: XCTestCase {
    func testRedactionMasksBearerToken() {
        let text = "Authorization: Bearer eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxIn0.sig"
        let redacted = Redactor.scrub(text)
        XCTAssertFalse(redacted.contains("eyJhbGciOiJSUzI1NiJ9"))
        XCTAssertTrue(redacted.contains("Bearer ***"))
    }

    func testRedactionMasksSignatureQuery() {
        let text = "GET https://cdn.example.com/a.mkv?sign=abc123&token=xyz&x=1"
        let redacted = Redactor.scrub(text)
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("xyz"))
        XCTAssertTrue(redacted.contains("x=1"))
    }

    func testRingBufferLimit() async {
        let center = DiagnosticsCenter(maxEntries: 5)
        for index in 0..<20 {
            await center.log(.info, "test", "entry \(index)")
        }
        let entries = await center.recent(limit: 100)
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries.last?.message, "entry 19")
    }

    func testExportFileContainsEntries() async throws {
        let center = DiagnosticsCenter(maxEntries: 10)
        await center.log(.error, "player", "播放失败：HTTP 403 sign=secret")
        let url = await center.exportFile()
        let content = try String(contentsOf: XCTUnwrap(url), encoding: .utf8)
        XCTAssertTrue(content.contains("播放失败"))
        XCTAssertFalse(content.contains("secret"))
    }
}
