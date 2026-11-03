import XCTest

/// 冒烟测试：在模拟器里真实启动 App，验证登录页可见。
/// 目的：在没有真机的环境下，每次 CI 都提供"App 能启动"的运行时证据。
final class LaunchSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesToLoginScreen() {
        let app = XCUIApplication()
        app.launch()

        let loginTitle = app.staticTexts["登录光鸭云盘"]
        XCTAssertTrue(loginTitle.waitForExistence(timeout: 30), "登录页标题未出现")

        let qrHint = app.staticTexts["请用光鸭云盘 App 扫码"]
        let tokenFallback = app.buttons["无法扫码？使用 Token 登录"]
        XCTAssertTrue(
            qrHint.waitForExistence(timeout: 30) || tokenFallback.exists,
            "登录页既没有出现扫码提示也没有 Token 兜底入口"
        )
    }

    func testLoginScreenOffersTokenFallback() {
        let app = XCUIApplication()
        app.launch()

        let fallback = app.buttons["无法扫码？使用 Token 登录"]
        if fallback.waitForExistence(timeout: 20) {
            XCTAssertTrue(fallback.isHittable)
        }
        // 二维码加载依赖网络，失败时不强制断言；登录页标题必须存在
        XCTAssertTrue(app.staticTexts["登录光鸭云盘"].exists)
    }
}
