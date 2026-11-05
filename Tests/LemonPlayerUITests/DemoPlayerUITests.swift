import XCTest

/// 演示播放页截图（无需登录）：验证沉浸式播放器 UI。
final class DemoPlayerUITests: XCTestCase {
    func testDemoPlayerScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoPlayer"]
        app.launch()
        sleep(3)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "ui-player-01"
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ui-player-01.png")
        try? shot.pngRepresentation.write(to: url)
        print("SCREENSHOT_PATH: \(url.path)")
        print("=== PLAYER_TREE ===")
        print(app.debugDescription)
        print("=== END PLAYER_TREE ===")
    }
}