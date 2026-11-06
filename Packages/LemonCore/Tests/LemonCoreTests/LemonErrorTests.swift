import XCTest
@testable import LemonCore

final class LemonErrorTests: XCTestCase {
    func testStatusCodeMapping() {
        XCTAssertEqual(LemonError.http(statusCode: 403, message: nil).statusCode, 403)
        XCTAssertEqual(LemonError.unauthorized(statusCode: 401, message: nil).statusCode, 401)
        XCTAssertNil(LemonError.transport("offline").statusCode)
        XCTAssertNil(LemonError.cancelled.statusCode)
    }

    func testRetryable() {
        XCTAssertTrue(LemonError.transport("timeout").isRetryable)
        XCTAssertTrue(LemonError.http(statusCode: 408, message: nil).isRetryable)
        XCTAssertTrue(LemonError.http(statusCode: 429, message: nil).isRetryable)
        XCTAssertTrue(LemonError.http(statusCode: 503, message: nil).isRetryable)
        XCTAssertFalse(LemonError.http(statusCode: 400, message: nil).isRetryable)
        XCTAssertFalse(LemonError.http(statusCode: 403, message: nil).isRetryable)
        XCTAssertFalse(LemonError.unauthorized(statusCode: 401, message: nil).isRetryable)
        XCTAssertFalse(LemonError.decoding("bad json").isRetryable)
    }

    func testUnauthorizedDetection() {
        XCTAssertTrue(LemonError.unauthorized(statusCode: 401, message: nil).isUnauthorized)
        XCTAssertTrue(LemonError.unauthorized(statusCode: 403, message: nil).isUnauthorized)
        XCTAssertFalse(LemonError.http(statusCode: 401, message: nil).isUnauthorized)
    }

    func testDiagnosticDescriptionHasStatusAndMessage() {
        let error = LemonError.http(statusCode: 502, message: "bad gateway")
        XCTAssertEqual(error.diagnosticDescription, "http(502): bad gateway")
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
    }

    func testWrap() {
        XCTAssertEqual(LemonError.wrap(LemonError.cancelled), .cancelled)
        XCTAssertEqual(LemonError.wrap(CancellationError()), .cancelled)
        let wrapped = LemonError.wrap(URLError(.timedOut))
        if case .unknown = wrapped {} else { XCTFail("应映射为 unknown") }
    }
}
