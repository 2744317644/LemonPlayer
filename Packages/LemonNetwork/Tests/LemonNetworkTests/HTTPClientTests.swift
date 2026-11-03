import XCTest
@testable import LemonNetwork

final class HTTPClientTests: XCTestCase {
    func testResponseSuccessRange() {
        XCTAssertTrue(HTTPResponse(statusCode: 200, data: Data()).isSuccess)
        XCTAssertTrue(HTTPResponse(statusCode: 204, data: Data()).isSuccess)
        XCTAssertFalse(HTTPResponse(statusCode: 400, data: Data()).isSuccess)
    }

    func testDecodeRoundTrip() throws {
        struct Payload: Codable, Equatable {
            let name: String
            let count: Int
        }
        let data = try JSONEncoder().encode(Payload(name: "lemon", count: 3))
        let response = HTTPResponse(statusCode: 200, data: data)
        XCTAssertEqual(try response.decode(Payload.self), Payload(name: "lemon", count: 3))
    }

    func testJSONRequestBodySetsContentType() throws {
        struct Payload: Encodable { let value: Int }
        let request = try HTTPRequest.json(
            url: URL(string: "https://example.com/api")!,
            body: Payload(value: 1)
        )
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertNotNil(request.body)
    }
}
