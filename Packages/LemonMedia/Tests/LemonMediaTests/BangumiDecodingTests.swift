import XCTest
@testable import LemonMedia

final class BangumiDecodingTests: XCTestCase {
    func testSubjectDecoding() throws {
        let json = #"""
        {
          "id": 265,
          "name": "新世紀エヴァンゲリオン",
          "name_cn": "新世纪福音战士",
          "summary": "简介",
          "date": "1995-10-04",
          "eps": 26,
          "total_episodes": 26,
          "images": {"large": "https://lain.bgm.tv/pic/cover/l/e5/69/265_Z5Uou.jpg", "common": "c", "medium": "m", "grid": "g", "small": "s"},
          "rating": {"score": 8.7, "total": 34799}
        }
        """#
        let subject = try JSONDecoder().decode(BangumiSubject.self, from: Data(json.utf8))
        XCTAssertEqual(subject.id, 265)
        XCTAssertEqual(subject.displayName, "新世纪福音战士")
        XCTAssertEqual(subject.totalEpisodes, 26)
        XCTAssertEqual(subject.rating?.score, 8.7)
        XCTAssertEqual(subject.coverURL?.absoluteString, "https://lain.bgm.tv/pic/cover/l/e5/69/265_Z5Uou.jpg")
    }

    func testSubjectFallbackToJapaneseName() throws {
        let json = #"{"id": 1, "name": "Original", "name_cn": ""}"#
        let subject = try JSONDecoder().decode(BangumiSubject.self, from: Data(json.utf8))
        XCTAssertEqual(subject.displayName, "Original")
        XCTAssertNil(subject.coverURL)
    }

    func testEpisodeDecoding() throws {
        let json = #"""
        {"id": 1, "subject_id": 265, "ep": 1, "sort": 1.0, "name": "使徒、襲来", "name_cn": "使徒袭来", "airdate": "1995-10-04", "type": 0}
        """#
        let episode = try JSONDecoder().decode(BangumiEpisode.self, from: Data(json.utf8))
        XCTAssertEqual(episode.subjectID, 265)
        XCTAssertEqual(episode.displayName, "第1话 使徒袭来")
    }

    func testEpisodeSortOnlyFallback() throws {
        let json = #"{"id": 2, "subject_id": 1, "sort": 12.0, "type": 0}"#
        let episode = try JSONDecoder().decode(BangumiEpisode.self, from: Data(json.utf8))
        XCTAssertEqual(episode.displayName, "第12话")
    }
}
