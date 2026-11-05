import XCTest

/// 登录流程 UI 走查：登录页 → 网页登录（WkWebView 加载官网）。
/// 截图写入模拟器临时目录，workflow 用 find 收集；同时打印无障碍树便于排查。
final class LoginFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testLoginScreenAndWebLogin() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["登录光鸭云盘"].waitForExistence(timeout: 60), "登录页未出现")
        capture(app, "ui-login-01-page")
        dump(app, "LOGIN_PAGE")

        // 账号密码入口
        let accountButton = app.buttons["使用账号密码登录"]
        if accountButton.waitForExistence(timeout: 10) {
            accountButton.tap()
            sleep(2)
            capture(app, "ui-login-02-account")
            dump(app, "ACCOUNT_SHEET")
            app.buttons["取消"].firstMatch.tap()
            sleep(1)
        }

        // 网页登录入口（WkWebView 加载 www.guangyapan.com/oauth/login）
        let webButton = app.buttons["网页登录"]
        if webButton.waitForExistence(timeout: 10) {
            webButton.tap()
            sleep(8)
            let webView = app.webViews.firstMatch
            if webView.waitForExistence(timeout: 20) {
                // 等官网登录表单（手机号/密码/验证码任一出现）
                _ = webView.staticTexts["密码登录"].waitForExistence(timeout: 15)
                capture(app, "ui-login-03-web")
                dump(app, "WEB_LOGIN")
                print("WEBVIEW_COUNT: \(webView.exists ? 1 : 0)")
                print("WEBVIEW_FRAME: \(webView.frame)")
                print("WEBVIEW_TEXT_COUNT: \(webView.staticTexts.count)")
                print("WEBVIEW_TEXTFIELDS: \(webView.textFields.count), SECURE: \(webView.secureTextFields.count)")
                let labels = webView.staticTexts.allElementsBoundByIndex.prefix(30).map { $0.label }
                print("WEBVIEW_LABELS: \(labels)")
            } else {
                print("WEBVIEW_MISSING")
            }
            if app.buttons["取消"].firstMatch.exists {
                app.buttons["取消"].firstMatch.tap()
            }
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
        print("SCREENSHOT_PATH: \(url.path)")
    }

    private func dump(_ app: XCUIApplication, _ label: String) {
        print("=== \(label) ===")
        print(app.debugDescription)
        print("=== END \(label) ===")
    }
}
