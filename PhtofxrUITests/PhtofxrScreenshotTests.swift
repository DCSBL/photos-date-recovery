import XCTest

/// Screenshots of the main screens in Dutch with the fake library. They stay in the result bundle; CI exports
/// them (scripts/ci/export_screenshots.py) and publishes them on the `screenshots` branch.
final class PhtofxrScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-phtofxrUITest", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The attachment name becomes the file name of the exported PNG.
    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testScanFlowScreenshots() {
        let app = launch()
        let scan = element(app, "scan")
        XCTAssertTrue(scan.waitForExistence(timeout: 60))
        snapshot(app, "01-start")

        scan.tap()
        let review = element(app, "section.review")
        XCTAssertTrue(review.waitForExistence(timeout: 30))
        snapshot(app, "02-resultaat")

        review.tap()
        let row = element(app, "row.import-11-0")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        snapshot(app, "03-te-beoordelen")

        row.tap()
        XCTAssertTrue(element(app, "proposedDate").waitForExistence(timeout: 15))
        snapshot(app, "04-detail")
    }

    @MainActor
    func testApplyFlowScreenshots() {
        let app = launch()
        let scan = element(app, "scan")
        XCTAssertTrue(scan.waitForExistence(timeout: 60))
        scan.tap()
        let review = element(app, "section.review")
        XCTAssertTrue(review.waitForExistence(timeout: 30))
        review.tap()

        let keepAll = element(app, "keepAllCertain")
        XCTAssertTrue(keepAll.waitForExistence(timeout: 15))
        keepAll.tap()
        snapshot(app, "07-bewaard")

        let openReview = element(app, "openReview")
        XCTAssertTrue(openReview.waitForExistence(timeout: 15))
        openReview.tap()
        let apply = element(app, "applyChanges")
        XCTAssertTrue(apply.waitForExistence(timeout: 15))
        snapshot(app, "08-controleren")

        apply.tap()
        XCTAssertTrue(element(app, "applyDone").waitForExistence(timeout: 30))
        snapshot(app, "09-toegepast")

        element(app, "closeReview").tap()
        let history = element(app, "history")
        XCTAssertTrue(history.waitForExistence(timeout: 15))
        history.tap()
        XCTAssertTrue(element(app, "revertBatch").waitForExistence(timeout: 15))
        snapshot(app, "10-geschiedenis")
    }

    @MainActor
    func testSettingsScreenshots() {
        let app = launch()
        let settings = element(app, "settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 60))
        settings.tap()
        XCTAssertTrue(app.switches["format.pixel"].waitForExistence(timeout: 15))
        snapshot(app, "05-instellingen")

        let diagnostics = element(app, "diagnostics")
        var swipes = 0
        while !diagnostics.exists && swipes < 10 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()
        let run = element(app, "runDiagnostics")
        XCTAssertTrue(run.waitForExistence(timeout: 15))
        run.tap()
        XCTAssertTrue(element(app, "diagnostics.total").waitForExistence(timeout: 30))
        snapshot(app, "06-diagnose")
    }
}
