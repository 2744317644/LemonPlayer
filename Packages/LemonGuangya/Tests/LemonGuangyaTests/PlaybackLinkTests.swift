import XCTest
@testable import LemonGuangya

final class PlaybackLinkTests: XCTestCase {
    func testSignedURLPreferred() throws {
        let json = #"""
        {"code":0,"msg":"success","data":{"signedURL":"https://cdn.example.com/a.mkv?sign=1","downloadUrl":"https://cdn.example.com/b.mkv"}}
        """#
        let link = try PlaybackLink.decode(from: Data(json.utf8))
        XCTAssertEqual(link.url.absoluteString, "https://cdn.example.com/a.mkv?sign=1")
        XCTAssertEqual(link.headers["Referer"], "https://www.guangyapan.com/")
        XCTAssertNotNil(link.headers["User-Agent"])
    }

    /// 2026-11-05 实测：成功响应没有 code 字段，只有 msg/data
    func testSuccessWithoutCodeField() throws {
        let json = #"""
        {"msg":"success","data":{"signedURL":"https://hwsh01-httpdown.guangyacdn.com/download/?fid=abc","urlDuration":21600}}
        """#
        let link = try PlaybackLink.decode(from: Data(json.utf8))
        XCTAssertEqual(link.url.absoluteString, "https://hwsh01-httpdown.guangyacdn.com/download/?fid=abc")
    }

    func testDownloadUrlFallback() throws {
        let json = #"""
        {"code":0,"msg":"success","data":{"signedURL":"","downloadUrl":"https://cdn.example.com/b.mkv"}}
        """#
        let link = try PlaybackLink.decode(from: Data(json.utf8))
        XCTAssertEqual(link.url.absoluteString, "https://cdn.example.com/b.mkv")
    }

    func testEmptyLinkThrows() {
        let json = #"""
        {"code":0,"msg":"success","data":{"signedURL":"","downloadUrl":""}}
        """#
        XCTAssertThrowsError(try PlaybackLink.decode(from: Data(json.utf8)))
    }

    func testErrorCodeThrows() {
        let json = #"""
        {"code":117,"msg":"无效token","data":null}
        """#
        XCTAssertThrowsError(try PlaybackLink.decode(from: Data(json.utf8)))
    }

    func testGarbagePayloadThrows() {
        XCTAssertThrowsError(try PlaybackLink.decode(from: Data("<html>502</html>".utf8)))
    }
}
