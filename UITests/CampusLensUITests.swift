import XCTest

@MainActor
final class CampusLensUITests: XCTestCase {
    func makeApp(fault: String = "",accessibility: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test","--fault",fault]
        if accessibility { app.launchArguments.append("--accessibility-test") }
        app.launch(); return app
    }
    func testOfflineCaptureConfirmationAndHistory() {
        let app = makeApp()
        app.buttons["prepare"].tap()
        XCTAssertTrue(app.buttons["shoot"].waitForExistence(timeout:5))
        app.buttons["shoot"].tap()
        XCTAssertTrue(app.buttons["confirm"].waitForExistence(timeout:10))
        scrollTo(app.buttons["confirm"],app:app)
        app.buttons["confirm"].tap()
        XCTAssertTrue(app.otherElements["parameters-nikon"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["起始参数 · 未校准"].firstMatch.exists)
        app.tabBars.buttons["历史"].tap()
        XCTAssertTrue(app.staticTexts["历史记录"].firstMatch.waitForExistence(timeout:5))
    }
    func testPermissionDeniedAndFailureAreVisible() {
        let denied = makeApp(fault:"denied")
        denied.buttons["prepare"].tap()
        XCTAssertTrue(denied.staticTexts["capture-message"].waitForExistence(timeout:5))
        assertMessage(denied.staticTexts["capture-message"],contains:"权限被拒绝")
        denied.terminate()
        let failure = makeApp(fault:"capture")
        failure.buttons["prepare"].tap()
        XCTAssertTrue(failure.buttons["shoot"].waitForExistence(timeout:5))
        failure.buttons["shoot"].tap()
        XCTAssertTrue(failure.buttons["prepare"].waitForExistence(timeout:5))
        assertMessage(failure.staticTexts["capture-message"],contains:"拍摄失败")
    }
    func testBackgroundAndLargeText() {
        enableSystemAccessibilitySettings()
        let app = makeApp(accessibility:true)
        scrollTo(app.buttons["prepare"],app:app)
        app.buttons["prepare"].tap()
        XCTAssertTrue(app.buttons["shoot"].waitForExistence(timeout:5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["prepare"].waitForExistence(timeout:5))
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["固定设备"].waitForExistence(timeout:5))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Settings-accessibility"; shot.lifetime = .keepAlways; add(shot)
    }
    func testNetworkTimeoutLeavesOfflineParameters() {
        let app = makeApp(fault:"timeout")
        app.buttons["prepare"].tap()
        XCTAssertTrue(app.buttons["shoot"].waitForExistence(timeout:5)); app.buttons["shoot"].tap()
        XCTAssertTrue(app.buttons["confirm"].waitForExistence(timeout:10)); scrollTo(app.buttons["confirm"],app:app); app.buttons["confirm"].tap()
        XCTAssertTrue(app.otherElements["parameters-nikon"].waitForExistence(timeout:10))
        scrollTo(app.staticTexts["ai-status"],app:app)
        assertMessage(app.staticTexts["ai-status"],contains:"离线结果保留")
        XCTAssertTrue(app.otherElements["parameters-canon"].exists)
    }
    func scrollTo(_ element: XCUIElement,app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
    }
    func assertMessage(_ element: XCUIElement,contains text: String) {
        let expectation = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@",text),object:element)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:5),.completed)
    }
    func enableSystemAccessibilitySettings() {
        // The environment accessors are read-only. Exercise actual simulator
        // Settings for motion/transparency; only font size and dark mode are
        // supplied by the Debug test modifier. The CI simulator is disposable.
        let settings = XCUIApplication(bundleIdentifier:"com.apple.Preferences")
        settings.launch()
        let accessibility = settings.staticTexts["Accessibility"].firstMatch
        scrollTo(accessibility,app:settings)
        XCTAssertTrue(accessibility.isHittable); accessibility.tap()
        let display = settings.staticTexts["Display & Text Size"].firstMatch
        XCTAssertTrue(display.waitForExistence(timeout:5)); display.tap()
        enableSystemSwitch("Reduce Transparency",in:settings)
        settings.navigationBars.buttons["Accessibility"].firstMatch.tap()
        let motion = settings.staticTexts["Motion"].firstMatch
        XCTAssertTrue(motion.waitForExistence(timeout:5)); motion.tap()
        enableSystemSwitch("Reduce Motion",in:settings)
        settings.terminate()
    }
    func enableSystemSwitch(_ name: String,in settings: XCUIApplication) {
        let toggle = settings.switches[name].firstMatch
        let row = settings.cells.containing(.switch,identifier:name).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:10))
        // Settings can expose a zero-frame AX switch during a transition. Use
        // its enclosing row's visible frame instead of the switch hit point.
        for _ in 0..<8 {
            let frame = row.frame
            if frame.width > 100 && frame.height > 20 && settings.frame.contains(CGPoint(x:frame.midX,y:frame.midY)) { break }
            settings.swipeUp()
        }
        let visible = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
            let frame = row.frame
            return row.exists && frame.width > 100 && frame.height > 20 && settings.frame.contains(CGPoint(x:frame.midX,y:frame.midY))
        },object:row)
        XCTAssertEqual(XCTWaiter.wait(for:[visible],timeout:10),.completed)
        if toggle.value as? String == "0" {
            row.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        }
        let enabled = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == '1'"),object:toggle)
        XCTAssertEqual(XCTWaiter.wait(for:[enabled],timeout:5),.completed)
    }
}
