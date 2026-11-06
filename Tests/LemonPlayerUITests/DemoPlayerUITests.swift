import XCTest

/// 演示播放页截图（无需登录）：验证沉浸式播放器 UI 与右侧面板。
final class DemoPlayerUITests: XCTestCase {
    private func save(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
        print("SCREENSHOT_PATH: \(url.path)")
    }

    func testDemoPlayerScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoPlayer"]
        app.launch()

        // 等演示流就绪；轻点画面唤出控制层
        sleep(3)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        save(XCUIScreen.main.screenshot(), name: "ui-player-01")

        // 打开右上角「更多」面板（右侧弹出样式）
        if app.buttons["更多"].waitForExistence(timeout: 3) {
            app.buttons["更多"].tap()
            sleep(1)
            save(XCUIScreen.main.screenshot(), name: "ui-player-02")
        }

        print("=== PLAYER_TREE ===")
        print(app.debugDescription)
        print("=== END PLAYER_TREE ===")
    }
}
