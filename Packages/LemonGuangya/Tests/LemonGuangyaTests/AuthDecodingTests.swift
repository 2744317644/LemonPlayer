import XCTest
@testable import LemonGuangya

final class AuthDecodingTests: XCTestCase {
    func testDeviceCodeDecodingFromRealResponseShape() throws {
        let json = #"""
        {
          "device_code": "AWrp64wt9HmyQUIZBmaFo3C4oJpX2EH4MoOPYuj3UgJ-6arEgA",
          "user_code": "AWrp64zaRXBZp3c0Kg",
          "expires_in": 120,
          "interval": 2,
          "verification_url": "https://account.guangyapan.com/__/auth/device/?client_id=x",
          "verification_uri_complete": "https://account.guangyapan.com/__/auth/device/?client_id=x&user_code=AWrp64zaRXBZp3c0Kg"
        }
        """#
        let code = try JSONDecoder().decode(DeviceCode.self, from: Data(json.utf8))
        XCTAssertEqual(code.expiresIn, 120)
        XCTAssertEqual(code.interval, 2)
        XCTAssertEqual(code.userCode, "AWrp64zaRXBZp3c0Kg")
        XCTAssertTrue(code.qrContent.hasSuffix("user_code=AWrp64zaRXBZp3c0Kg"))
    }

    func testPendingPollIsNotAnError() {
        let json = #"{"error":"authorization_pending","error_code":4050,"error_description":"Precondition Required"}"#
        let result = DevicePollResult.decode(data: Data(json.utf8), statusCode: 400)
        XCTAssertEqual(result, .pending)
    }

    func testExpiredPoll() {
        let json = #"{"error":"expired_token","error_code":1,"error_description":"expired"}"#
        XCTAssertEqual(DevicePollResult.decode(data: Data(json.utf8), statusCode: 400), .expired)
    }

    func testAuthorizedPoll() throws {
        let json = #"""
        {"access_token":"eyJhbGciOiJSUzI1NiJ9.e30.sig","refresh_token":"r1","expires_in":3600,"token_type":"Bearer","sub":"user-123"}
        """#
        let result = DevicePollResult.decode(data: Data(json.utf8), statusCode: 200)
        guard case .authorized(let bundle) = result else {
            return XCTFail("expected authorized, got \(result)")
        }
        XCTAssertEqual(bundle.accessToken, "eyJhbGciOiJSUzI1NiJ9.e30.sig")
        XCTAssertEqual(bundle.refreshToken, "r1")
        XCTAssertEqual(bundle.subject, "user-123")
        XCTAssertEqual(bundle.expiresIn, 3600)
    }

    func testGarbagePayloadFailsGracefully() {
        let result = DevicePollResult.decode(data: Data("<html>502</html>".utf8), statusCode: 502)
        guard case .failed = result else {
            return XCTFail("expected failed, got \(result)")
        }
    }

    func testDeviceIdentityShape() {
        let identity = DeviceIdentity.random()
        XCTAssertEqual(identity.deviceID.count, 32)
        XCTAssertTrue(identity.deviceID.allSatisfy { $0.isHexDigit })
        XCTAssertTrue(identity.sign.hasPrefix("wdi10."))
        XCTAssertTrue(identity.sign.contains(identity.deviceID))
    }

    func testLenientDecodeTopLevel() throws {
        let json = #"""
        {"access_token":"a1","refresh_token":"r1","expires_in":60,"sub":"u1"}
        """#
        let bundle = try TokenBundle.decodeLenient(from: Data(json.utf8))
        XCTAssertEqual(bundle.accessToken, "a1")
        XCTAssertEqual(bundle.refreshToken, "r1")
        XCTAssertEqual(bundle.expiresIn, 60)
        XCTAssertEqual(bundle.subject, "u1")
    }

    func testLenientDecodeNestedData() throws {
        let json = #"""
        {"code":0,"data":{"access_token":"a2","refresh_token":"r2","expires_in":120,"sub":"u2"}}
        """#
        let bundle = try TokenBundle.decodeLenient(from: Data(json.utf8))
        XCTAssertEqual(bundle.accessToken, "a2")
        XCTAssertEqual(bundle.refreshToken, "r2")
        XCTAssertEqual(bundle.expiresIn, 120)
        XCTAssertEqual(bundle.subject, "u2")
    }

    func testLenientDecodeMissingTokenThrows() {
        XCTAssertThrowsError(try TokenBundle.decodeLenient(from: Data("{}".utf8)))
    }
}
