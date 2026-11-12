import XCTest

/// Smoke tests against the fake library (`-phtofxrUITest`): scan, browse a section, open a photo, run diagnostics.
/// The same tests run on iPhone and iPhone Duo; they only use identifiers, so they work collapsed and side by side.
final class PhtofxrUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-phtofxrUITest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func testScanShowsSectionsAndDetail() {
        let app = launch()
        let scan = element(app, "scan")
        XCTAssertTrue(scan.waitForExistence(timeout: 60), "Scan button missing")
        scan.tap()

        let review = element(app, "section.review")
        XCTAssertTrue(review.waitForExistence(timeout: 30), "Result sections did not appear after scanning")
        XCTAssertTrue(element(app, "section.suspicious").exists)
        XCTAssertTrue(element(app, "section.noDateInName").exists)
        review.tap()

        let row = element(app, "row.import-11-0")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "First photo of the 11 October import is not listed")
        row.tap()

        XCTAssertTrue(element(app, "proposedDate").waitForExistence(timeout: 15), "Detail shows no proposed date")
    }

    @MainActor
    func testDiagnostics() {
        let app = launch()
        let settings = element(app, "settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 60))
        settings.tap()

        // Diagnostics sits below the format list; the form only creates rows once they scroll into view.
        XCTAssertTrue(app.switches["format.pixel"].waitForExistence(timeout: 15))
        let diagnostics = element(app, "diagnostics")
        var swipes = 0
        while !diagnostics.exists && swipes < 10 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5), "Diagnostics row not found after scrolling")
        diagnostics.tap()

        let run = element(app, "runDiagnostics")
        XCTAssertTrue(run.waitForExistence(timeout: 15))
        run.tap()
        XCTAssertTrue(element(app, "diagnostics.total").waitForExistence(timeout: 30), "Diagnostics report missing")
    }

    @MainActor
    func testFormatsCanBeSwitchedOff() {
        let app = launch()
        let settings = element(app, "settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 60))
        settings.tap()

        let whatsapp = app.switches["format.whatsapp"]
        XCTAssertTrue(whatsapp.waitForExistence(timeout: 15))
        XCTAssertEqual(whatsapp.value as? String, "1")
        whatsapp.switches.firstMatch.tap()
        XCTAssertEqual(whatsapp.value as? String, "0")
    }
}
