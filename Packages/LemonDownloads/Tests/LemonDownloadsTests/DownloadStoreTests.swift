import XCTest
@testable import LemonDownloads

final class DownloadStoreTests: XCTestCase {
    private func makeStore() -> DownloadStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("download-store-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return DownloadStore(directory: directory)
    }

    func testRecordsRoundTrip() {
        let store = makeStore()
        let records = [
            DownloadRecord(id: "1", fileName: "a.mkv", parentID: "p", state: .completed, totalBytes: 100, downloadedBytes: 100),
            DownloadRecord(id: "2", fileName: "b.mkv", parentID: "p", state: .paused, totalBytes: 200, downloadedBytes: 50)
        ]
        store.save(records)
        XCTAssertEqual(store.load(), records)
    }

    func testResumeDataRoundTrip() {
        let store = makeStore()
        let data = Data("resume".utf8)
        store.saveResumeData(data, id: "42")
        XCTAssertEqual(store.resumeData(id: "42"), data)
        store.removeResumeData(id: "42")
        XCTAssertNil(store.resumeData(id: "42"))
    }
}
