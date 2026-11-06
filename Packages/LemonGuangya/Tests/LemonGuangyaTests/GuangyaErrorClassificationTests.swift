import XCTest
@testable import LemonGuangya

final class GuangyaErrorClassificationTests: XCTestCase {
    func testAuthFailureCodes() {
        XCTAssertTrue(GuangyaError.tokenExpired.isAuthFailure)
        XCTAssertTrue(GuangyaError.unauthorized.isAuthFailure)
        XCTAssertTrue(GuangyaError.api(code: 117, message: "无效token").isAuthFailure)
        XCTAssertTrue(GuangyaError.requestFailed(statusCode: 401, message: "").isAuthFailure)
        XCTAssertTrue(GuangyaError.requestFailed(statusCode: 403, message: "").isAuthFailure)
    }

    func testNonAuthFailureCodes() {
        XCTAssertFalse(GuangyaError.api(code: 4022, message: "账号或密码错误").isAuthFailure)
        XCTAssertFalse(GuangyaError.api(code: 143, message: "文件不存在").isAuthFailure)
        XCTAssertFalse(GuangyaError.requestFailed(statusCode: 500, message: "").isAuthFailure)
    }

    func testStatusCodeMapping() {
        XCTAssertEqual(GuangyaError.tokenExpired.statusCode, 401)
        XCTAssertEqual(GuangyaError.api(code: 117, message: "").statusCode, 401)
        XCTAssertEqual(GuangyaError.api(code: 403, message: "").statusCode, 403)
        XCTAssertNil(GuangyaError.api(code: 4022, message: "").statusCode)
        XCTAssertEqual(GuangyaError.requestFailed(statusCode: 502, message: "").statusCode, 502)
        XCTAssertEqual(GuangyaError.api(code: 117, message: "").apiCode, 117)
    }
}
