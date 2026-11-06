import XCTest
@testable import LemonNetwork

final class HTTPPolicyTests: XCTestCase {
    func testRetryPolicyAttemptBudget() {
        let policy = HTTPRetryPolicy(maxAttempts: 3)
        XCTAssertTrue(policy.shouldRetry(statusCode: 503, attempt: 1))
        XCTAssertTrue(policy.shouldRetry(statusCode: 503, attempt: 2))
        XCTAssertFalse(policy.shouldRetry(statusCode: 503, attempt: 3))
    }

    func testRetryPolicyOnlyRetryableStatusCodes() {
        let policy = HTTPRetryPolicy()
        XCTAssertTrue(policy.shouldRetry(statusCode: 429, attempt: 1))
        XCTAssertTrue(policy.shouldRetry(statusCode: 502, attempt: 1))
        XCTAssertFalse(policy.shouldRetry(statusCode: 400, attempt: 1))
        XCTAssertFalse(policy.shouldRetry(statusCode: 403, attempt: 1))
    }

    func testRetryPolicyDoesNotRetryCancellation() {
        let policy = HTTPRetryPolicy(maxAttempts: 3)
        XCTAssertFalse(policy.shouldRetry(transportError: CancellationError(), attempt: 1))
        XCTAssertFalse(policy.shouldRetry(transportError: URLError(.cancelled), attempt: 1))
        XCTAssertTrue(policy.shouldRetry(transportError: URLError(.timedOut), attempt: 1))
    }

    func testExponentialBackoffIsCapped() {
        let policy = HTTPRetryPolicy(maxAttempts: 5, baseDelay: 0.5, maxDelay: 2)
        XCTAssertEqual(policy.delay(forAttempt: 1), 0.5, accuracy: 0.001)
        XCTAssertEqual(policy.delay(forAttempt: 2), 1.0, accuracy: 0.001)
        XCTAssertEqual(policy.delay(forAttempt: 3), 2.0, accuracy: 0.001)
        XCTAssertEqual(policy.delay(forAttempt: 4), 2.0, accuracy: 0.001)
    }

    func testConfigurationPresets() {
        XCTAssertNotNil(HTTPClientConfiguration.default.userAgent)
        XCTAssertEqual(HTTPClientConfiguration.bangumi.userAgent, HTTPUserAgents.bangumi)
        XCTAssertEqual(HTTPClientConfiguration.bangumi.retryPolicy.maxAttempts, 3)
        XCTAssertNil(HTTPClientConfiguration.default.defaultHeaders["User-Agent"])
    }

    func testRateLimiterRespectsMinimumInterval() async {
        let limiter = RateLimiter(minimumInterval: 0.15)
        let start = Date()
        await limiter.wait()
        await limiter.wait()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(elapsed, 0.14)
    }
}
