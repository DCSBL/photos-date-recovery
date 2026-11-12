import XCTest

/// Screenshots of the main screens in Dutch with the fake library. They stay in the result bundle; CI exports
/// them (scripts/ci/export_screenshots.py) and publishes them on the `screenshots` branch.
final class PhtofxrScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(withoutColor: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-phtofxrUITest", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"]
        if withoutColor { app.launchArguments.append("-phtofxrWithoutColor") }
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
    private func tap(_ app: XCUIApplication, _ identifier: String) {
        let target = element(app, identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 30), "\(identifier) not found")
        target.tap()
    }

    /// Scan, then open the 11 October import in "To review".
    @MainActor
    private func openOctoberImport(_ app: XCUIApplication) {
        tap(app, "scan")
        tap(app, "section.review")
        tap(app, "import.2016-10-11")
        XCTAssertTrue(element(app, "row.import-11-0").waitForExistence(timeout: 15))
    }

    @MainActor
    func testScanFlowScreenshots() {
        let app = launch()
        XCTAssertTrue(element(app, "scan").waitForExistence(timeout: 60))
        snapshot(app, "01-start")

        tap(app, "scan")
        XCTAssertTrue(element(app, "section.review").waitForExistence(timeout: 30))
        snapshot(app, "02-resultaat")

        tap(app, "section.review")
        XCTAssertTrue(element(app, "import.2016-10-11").waitForExistence(timeout: 15))
        snapshot(app, "03-imports")

        tap(app, "import.2016-10-11")
        XCTAssertTrue(element(app, "row.import-11-0").waitForExistence(timeout: 15))
        snapshot(app, "04-import")

        tap(app, "row.import-11-0")
        XCTAssertTrue(element(app, "proposedDate").waitForExistence(timeout: 15))
        snapshot(app, "05-detail")

        let otherDate = element(app, "otherDate")
        var swipes = 0
        while !otherDate.waitForExistence(timeout: 2) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        otherDate.tap()
        XCTAssertTrue(element(app, "datePicker").waitForExistence(timeout: 15))
        snapshot(app, "06-andere-datum")
    }

    /// The same import and photo with Differentiate Without Color: underlines instead of colors.
    @MainActor
    func testWithoutColorScreenshots() {
        let app = launch(withoutColor: true)
        XCTAssertTrue(element(app, "scan").waitForExistence(timeout: 60))
        openOctoberImport(app)
        snapshot(app, "07-import-zonder-kleur")

        tap(app, "row.import-11-0")
        XCTAssertTrue(element(app, "proposedDate").waitForExistence(timeout: 15))
        snapshot(app, "08-detail-zonder-kleur")
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
        snapshot(app, "09-bewaard")

        let openReview = element(app, "openReview")
        XCTAssertTrue(openReview.waitForExistence(timeout: 15))
        openReview.tap()
        let apply = element(app, "applyChanges")
        XCTAssertTrue(apply.waitForExistence(timeout: 15))
        snapshot(app, "10-controleren")

        apply.tap()
        XCTAssertTrue(element(app, "applyDone").waitForExistence(timeout: 30))
        snapshot(app, "11-toegepast")

        let history = element(app, "showHistory")
        XCTAssertTrue(history.waitForExistence(timeout: 15))
        history.tap()
        XCTAssertTrue(element(app, "revertBatch").waitForExistence(timeout: 15))
        snapshot(app, "12-geschiedenis")
    }

    @MainActor
    func testSettingsScreenshots() {
        let app = launch()
        let settings = element(app, "settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 60))
        settings.tap()
        XCTAssertTrue(app.switches["format.pixel"].waitForExistence(timeout: 15))
        snapshot(app, "13-instellingen")

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
        snapshot(app, "14-diagnose")
    }
}
