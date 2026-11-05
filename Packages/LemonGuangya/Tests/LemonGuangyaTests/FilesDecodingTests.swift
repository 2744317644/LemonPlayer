import XCTest
@testable import LemonGuangya

final class FilesDecodingTests: XCTestCase {
    private let listJSON = #"""
    {
      "code": 0,
      "msg": "success",
      "data": {
        "total": 3,
        "list": [
          {
            "fileId": "dir-1",
            "parentId": "",
            "fileName": "动漫",
            "fileSize": 0,
            "resType": 2,
            "fileType": 0,
            "utime": 1790000000
          },
          {
            "fileId": "file-1",
            "parentId": "dir-1",
            "fileName": "葬送的芙莉莲 第01话.mkv",
            "fileSize": 1234567890,
            "resType": 1,
            "fileType": 2,
            "ext": "mkv",
            "utime": 1790000100
          },
          {
            "fileId": 998877,
            "parentId": "dir-1",
            "fileName": "字幕",
            "resType": 2
          }
        ]
      }
    }
    """#

    func testFileListDecoding() throws {
        struct Envelope: Decodable {
            struct Payload: Decodable {
                let total: Int
                let list: [GuangyaFile]
            }
            let code: Int
            let data: Payload
        }

        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(listJSON.utf8))
        XCTAssertEqual(envelope.code, 0)
        XCTAssertEqual(envelope.data.total, 3)
        XCTAssertEqual(envelope.data.list.count, 3)

        let folder = envelope.data.list[0]
        XCTAssertTrue(folder.isFolder)
        XCTAssertEqual(folder.name, "动漫")
        XCTAssertNotNil(folder.modifiedAt)

        let video = envelope.data.list[1]
        XCTAssertEqual(video.kind, .video)
        XCTAssertTrue(video.isPlayable)
        XCTAssertEqual(video.size, 1234567890)
        XCTAssertEqual(video.ext, "mkv")

        // 数字型 fileId 也要能解析
        XCTAssertEqual(envelope.data.list[2].id, "998877")
    }

    func testKindMapping() {
        XCTAssertEqual(FileKind(resType: 2, fileType: nil), .folder)
        XCTAssertEqual(FileKind(resType: 1, fileType: 2), .video)
        XCTAssertEqual(FileKind(resType: 1, fileType: 3), .audio)
        XCTAssertEqual(FileKind(resType: 1, fileType: 99), .other)
    }

    func testPaginationTermination() {
        let short = FileListPage(total: 500, items: Array(repeating: GuangyaFile(id: "x", parentID: "", name: "x", size: 0, kind: .other), count: 2))
        XCTAssertFalse(short.hasMore(pageSize: 100, accumulated: 2))

        let full = FileListPage(total: 500, items: Array(repeating: GuangyaFile(id: "y", parentID: "", name: "y", size: 0, kind: .other), count: 100))
        XCTAssertTrue(full.hasMore(pageSize: 100, accumulated: 100))
    }

    /// 2026-11-05 真实响应：成功时没有 code 字段，只有 msg/data
    func testParseRealSuccessResponseWithoutCode() throws {
        let json = #"""
        {"msg":"success","data":{"total":2,"list":[
          {"fileId":"1947716972652265556","fileName":"番剧","resType":2,"dirType":1,"utime":1790428322},
          {"fileId":"1953324602431963199","fileName":"第01话.mkv","parentId":"1947716972652265556","resType":1,"fileType":2,"fileSize":123,"utime":1790428323}
        ]}}
        """#
        let page = try GuangyaFileService.parseFileListResponse(Data(json.utf8))
        XCTAssertEqual(page.total, 2)
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.items[0].kind, .folder)
        XCTAssertEqual(page.items[1].kind, .video)
        XCTAssertEqual(page.items[1].name, "第01话.mkv")
    }

    /// 错误响应仍带 code（117 = token 失效）
    func testParseErrorResponseCode() {
        let json = #"{"code":117,"msg":"无效token","data":null}"#
        XCTAssertThrowsError(try GuangyaFileService.parseFileListResponse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? GuangyaError, .tokenExpired)
        }
    }
}
