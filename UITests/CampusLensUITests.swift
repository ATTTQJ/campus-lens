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
    func testAdjustmentPreviewUndoRestoreAndHiddenSubjectFrames() {
        let app = makeApp()
        app.buttons["prepare"].tap()
        XCTAssertTrue(app.buttons["shoot"].waitForExistence(timeout:5))
        let finder = app.otherElements["capture-viewfinder"]
        XCTAssertTrue(finder.waitForExistence(timeout:5))
        XCTAssertEqual(finder.frame.width/finder.frame.height,0.75,accuracy:0.01)
        XCTAssertGreaterThanOrEqual(app.buttons["shoot"].frame.minY,finder.frame.maxY)
        keepScreenshot(app,"Capture-glass")
        app.buttons["shoot"].tap()
        XCTAssertTrue(app.buttons["confirm"].waitForExistence(timeout:10))
        scrollTo(app.buttons["confirm"],app:app); app.buttons["confirm"].tap()
        XCTAssertTrue(app.otherElements["parameters-nikon"].waitForExistence(timeout:10))
        XCTAssertFalse(app.otherElements["subject-regions"].exists)
        for _ in 0..<5 { if app.buttons["adjust-nikon"].isHittable { break }; app.swipeDown() }
        scrollTo(app.buttons["adjust-nikon"],app:app); keepScreenshot(app,"Results-glass")
        app.buttons["adjust-nikon"].tap()
        XCTAssertTrue(app.buttons["feedback-faster"].waitForExistence(timeout:5))
        app.buttons["feedback-faster"].tap()
        XCTAssertTrue(app.buttons["apply-adjustment"].waitForExistence(timeout:10))
        keepScreenshot(app,"Adjustment-preview-glass")
        app.buttons["apply-adjustment"].tap()
        assertMessage(app.staticTexts["adjustment-count"],contains:"1 次")
        scrollTo(app.buttons["undo-adjustment"],app:app)
        XCTAssertTrue(app.buttons["undo-adjustment"].isEnabled)
        keepScreenshot(app,"Adjustment-undo-glass")
        app.buttons["undo-adjustment"].tap()
        assertMessage(app.staticTexts["adjustment-count"],contains:"0 次")
        for _ in 0..<5 { if app.buttons["feedback-faster"].isHittable { break }; app.swipeDown() }
        app.buttons["feedback-faster"].tap()
        XCTAssertTrue(app.buttons["apply-adjustment"].waitForExistence(timeout:10)); app.buttons["apply-adjustment"].tap()
        assertMessage(app.staticTexts["adjustment-count"],contains:"1 次")
        scrollTo(app.buttons["restore-adjustment"],app:app); app.buttons["restore-adjustment"].tap()
        XCTAssertTrue(app.buttons["apply-adjustment"].waitForExistence(timeout:10)); app.buttons["apply-adjustment"].tap()
        XCTAssertTrue(app.buttons["restore-adjustment"].waitForExistence(timeout:5))
        let restored = XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == NO"),object:app.buttons["restore-adjustment"])
        XCTAssertEqual(XCTWaiter.wait(for:[restored],timeout:10),.completed)
    }
    func keepScreenshot(_ app: XCUIApplication,_ name: String) {
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
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
        // Settings may publish the row before its switch value is available on
        // a cold boot. Wait for a known value and only tap a verified off state.
        for _ in 0..<2 {
            let known = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value IN {'0','1'}"),object:toggle)
            guard XCTWaiter.wait(for:[known],timeout:15) == .completed else {
                XCTFail("Settings did not expose a stable value for \(name)"); return
            }
            if toggle.value as? String == "1" { return }
            guard toggle.value as? String == "0" else { continue }
            if toggle.isHittable && toggle.frame.width > 20 { toggle.tap() }
            else { row.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap() }
            let enabled = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == '1'"),object:toggle)
            if XCTWaiter.wait(for:[enabled],timeout:15) == .completed { return }
        }
        XCTAssertEqual(toggle.value as? String,"1","Failed to enable \(name) in actual simulator Settings")
    }
}
