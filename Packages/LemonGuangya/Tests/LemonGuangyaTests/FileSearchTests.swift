import XCTest
@testable import LemonGuangya

final class FileSearchTests: XCTestCase {
    private var files: [GuangyaFile] {
        [
            GuangyaFile(id: "1", parentID: "", name: "葬送的芙莉莲 第01话.mkv", size: 1, kind: .video),
            GuangyaFile(id: "2", parentID: "", name: "Frieren S01E02.mkv", size: 1, kind: .video),
            GuangyaFile(id: "3", parentID: "", name: "字幕", size: 0, kind: .folder)
        ]
    }

    func testEmptyQueryReturnsAll() {
        XCTAssertEqual(FileSearch.filter(files, query: "   ").count, 3)
    }

    func testChineseQueryMatches() {
        let result = FileSearch.filter(files, query: "芙莉莲")
        XCTAssertEqual(result.map(\.id), ["1"])
    }

    func testCaseInsensitiveEnglish() {
        XCTAssertEqual(FileSearch.filter(files, query: "frieren").map(\.id), ["2"])
        XCTAssertEqual(FileSearch.filter(files, query: "FRIEREN").map(\.id), ["2"])
    }

    func testNoMatch() {
        XCTAssertTrue(FileSearch.filter(files, query: "不存在的名字").isEmpty)
    }
}
