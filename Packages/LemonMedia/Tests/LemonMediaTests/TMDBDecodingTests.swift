import XCTest
@testable import LemonMedia

final class TMDBDecodingTests: XCTestCase {
    func testSearchResultDecoding() throws {
        let json = #"""
        {"results":[
          {"id":1084242,"media_type":"movie","title":"葬送的芙莉莲","release_date":"2024-09-20","poster_path":"/abc.jpg","vote_average":8.4,"overview":"概述"},
          {"id":209867,"media_type":"tv","name":"葬送的芙莉莲","first_air_date":"2023-09-29","poster_path":"/tv.jpg","vote_average":8.7,"overview":"概述"}
        ]}
        """#
        struct Envelope: Decodable { let results: [TMDBSearchResult] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.results.count, 2)
        XCTAssertEqual(envelope.results[0].displayTitle, "葬送的芙莉莲")
        XCTAssertEqual(envelope.results[0].year, 2024)
        XCTAssertEqual(envelope.results[1].year, 2023)
        XCTAssertEqual(envelope.results[0].posterURL?.absoluteString, "https://image.tmdb.org/t/p/w500/abc.jpg")
    }

    func testPosterURLHelper() {
        XCTAssertNil(TMDBClient.posterURL(for: nil))
        XCTAssertNil(TMDBClient.posterURL(for: ""))
        XCTAssertEqual(
            TMDBClient.posterURL(for: "/x/y.jpg")?.absoluteString,
            "https://image.tmdb.org/t/p/w500/x/y.jpg"
        )
    }
}
