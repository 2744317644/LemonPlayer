import XCTest
@testable import LemonDownloads

final class DownloadStateMachineTests: XCTestCase {
    private func record(_ state: DownloadState) -> DownloadRecord {
        DownloadRecord(id: "f1", fileName: "a.mkv", parentID: "p", state: state, totalBytes: 100, downloadedBytes: 10)
    }

    func testHappyPath() {
        var record = record(.queued)
        XCTAssertEqual(record.progressFraction, 0.1)

        record = DownloadStateMachine.apply(record, to: .downloading)
        XCTAssertEqual(record.state, .downloading)

        record = DownloadStateMachine.apply(record, to: .completed)
        XCTAssertEqual(record.state, .completed)
        XCTAssertEqual(record.downloadedBytes, 100)
        XCTAssertEqual(record.progressFraction, 1.0)
    }

    func testPauseResume() {
        var record = record(.downloading)
        record = DownloadStateMachine.apply(record, to: .paused)
        XCTAssertEqual(record.state, .paused)
        record = DownloadStateMachine.apply(record, to: .downloading)
        XCTAssertEqual(record.state, .downloading)
    }

    func testIllegalTransitionsRejected() {
        let completed = record(.completed)
        XCTAssertEqual(DownloadStateMachine.apply(completed, to: .downloading).state, .completed)
        XCTAssertFalse(DownloadStateMachine.canTransition(from: .completed, to: .paused))
        XCTAssertFalse(DownloadStateMachine.canTransition(from: .cancelled, to: .completed))
    }

    func testFailureThenRetry() {
        var record = record(.downloading)
        record = DownloadStateMachine.apply(record, to: .failed)
        XCTAssertEqual(record.state, .failed)
        record = DownloadStateMachine.apply(record, to: .queued)
        XCTAssertEqual(record.state, .queued)
        XCTAssertNil(record.errorMessage)
    }

    func testProgressClamped() {
        let over = DownloadRecord(id: "x", fileName: "x", parentID: "", totalBytes: 100, downloadedBytes: 150)
        XCTAssertEqual(over.progressFraction, 1.0)
        let unknown = DownloadRecord(id: "y", fileName: "y", parentID: "", totalBytes: 0, downloadedBytes: 10)
        XCTAssertEqual(unknown.progressFraction, 0)
    }
}
