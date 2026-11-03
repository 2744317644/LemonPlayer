import XCTest
@testable import LemonSubtitle

final class SubtitleTextDecoderTests: XCTestCase {
    func testUTF8Plain() {
        let result = SubtitleTextDecoder.decode(Data("中文 UTF-8".utf8))
        XCTAssertEqual(result.text, "中文 UTF-8")
        XCTAssertEqual(result.encoding, .utf8)
    }

    func testUTF8WithBOM() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("带 BOM 的字幕".utf8))
        let result = SubtitleTextDecoder.decode(data)
        XCTAssertEqual(result.text, "带 BOM 的字幕")
    }

    func testGB18030Chinese() throws {
        #if canImport(Darwin)
        // “中文” 的 GBK/GB18030 字节（Apple 平台才有 GB18030 解码）
        let data = Data([0xD6, 0xD0, 0xCE, 0xC4])
        let result = SubtitleTextDecoder.decode(data)
        XCTAssertEqual(result.text, "中文")
        XCTAssertEqual(result.encoding, SubtitleTextDecoder.gb18030)
        #else
        throw XCTSkip("Linux Foundation 不支持 GB18030 解码")
        #endif
    }

    func testUTF16LEWithBOM() {
        let data = "字幕".data(using: .utf16LittleEndian)!
        var withBOM = Data([0xFF, 0xFE])
        withBOM.append(data)
        let result = SubtitleTextDecoder.decode(withBOM)
        XCTAssertEqual(result.text, "字幕")
    }

    func testLatin1FallbackDoesNotCrash() {
        let data = Data([0x00, 0x01, 0x02, 0xFF])
        let result = SubtitleTextDecoder.decode(data)
        XCTAssertFalse(result.text.isEmpty)
    }
}
