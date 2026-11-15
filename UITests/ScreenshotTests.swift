import XCTest

/// 在真机上截取主要页面，用于检查界面（只浏览，不修改数据）
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
        let agree = app.buttons["我已了解，同意并继续"]
        if agree.waitForExistence(timeout: 2) { agree.tap() }
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testCaptureMainScreens() {
        sleep(1)
        shot("1-scan-photo")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "链接")).firstMatch.tap()
        sleep(1)
        shot("2-scan-link")

        app.tabBars.buttons["历史"].tap()
        sleep(1)
        shot("3-history")
        let cells = app.cells
        if cells.count > 1 {
            cells.element(boundBy: 1).tap()
            sleep(2)
            shot("4-result-top")
            app.swipeUp()
            sleep(1)
            shot("5-result-middle")
            app.swipeUp()
            app.swipeUp()
            sleep(1)
            shot("6-result-bottom")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        app.tabBars.buttons["设置"].tap()
        sleep(1)
        shot("7-settings")
    }
}
