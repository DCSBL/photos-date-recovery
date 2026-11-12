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

        let october = element(app, "import.2016-10-11")
        XCTAssertTrue(october.waitForExistence(timeout: 15), "The 11 October import is not listed")
        october.tap()

        let row = element(app, "row.import-11-0")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "First photo of the 11 October import is not listed")
        row.tap()

        XCTAssertTrue(element(app, "proposedDate").waitForExistence(timeout: 15), "Detail shows no proposed date")
        XCTAssertTrue(element(app, "filename").exists)
    }

    @MainActor
    func testPickDateForPhotoWithoutDateInName() {
        let app = launch()
        let scan = element(app, "scan")
        XCTAssertTrue(scan.waitForExistence(timeout: 60))
        scan.tap()

        let noDate = element(app, "section.noDateInName")
        XCTAssertTrue(noDate.waitForExistence(timeout: 30))
        noDate.tap()
        let october = element(app, "import.2016-10-11")
        XCTAssertTrue(october.waitForExistence(timeout: 15))
        october.tap()
        let row = element(app, "row.import-11-3")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "IMG_0003.JPG is not listed")
        row.tap()

        let otherDate = element(app, "otherDate")
        scroll(app, to: otherDate)
        otherDate.tap()

        // IMG_0003.JPG was imported right after 2014-03-03 20.17.02.jpg.
        let previous = element(app, "pick.previous")
        XCTAssertTrue(previous.waitForExistence(timeout: 15), "No quick pick from the previous photo")
        let save = element(app, "saveDate")
        XCTAssertFalse(save.isEnabled, "Keeping the date Photos already has should not be possible")
        previous.tap()
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let kept = element(app, "keptLabel")
        scroll(app, to: kept)
        XCTAssertTrue(element(app, "manualDate").exists, "Detail does not show the picked date")
        XCTAssertTrue(element(app, "undoKeep").exists)
    }

    /// Forms only create rows once they scroll into view.
    @MainActor
    private func scroll(_ app: XCUIApplication, to target: XCUIElement) {
        var swipes = 0
        while !target.waitForExistence(timeout: 2) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(target.exists, "\(target) not found after scrolling")
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

/// Keep, review, apply and revert against the fake library.
final class PhtofxrApplyUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func testKeepReviewApplyAndRevert() {
        let app = XCUIApplication()
        app.launchArguments = ["-phtofxrUITest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let scan = element(app, "scan")
        XCTAssertTrue(scan.waitForExistence(timeout: 60))
        scan.tap()
        let review = element(app, "section.review")
        XCTAssertTrue(review.waitForExistence(timeout: 30))
        review.tap()

        let keepAll = element(app, "keepAllCertain")
        XCTAssertTrue(keepAll.waitForExistence(timeout: 15))
        keepAll.tap()
        let openReview = element(app, "openReview")
        XCTAssertTrue(openReview.waitForExistence(timeout: 15))
        XCTAssertTrue(openReview.isEnabled, "Review button stays disabled after keeping all certain proposals")
        openReview.tap()

        let apply = element(app, "applyChanges")
        XCTAssertTrue(apply.waitForExistence(timeout: 15))
        apply.tap()
        XCTAssertTrue(element(app, "applyDone").waitForExistence(timeout: 30), "Applying did not finish")

        // The sidebar's History button is hidden while a list is pushed on a narrow window; the result offers it.
        let history = element(app, "showHistory")
        XCTAssertTrue(history.waitForExistence(timeout: 15))
        history.tap()
        let revert = element(app, "revertBatch")
        XCTAssertTrue(revert.waitForExistence(timeout: 15), "History shows no revertable batch")
        revert.tap()

        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Revert' AND identifier != 'revertBatch'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 15), "No confirmation for the revert")
        confirm.tap()
        XCTAssertTrue(element(app, "revertDone").waitForExistence(timeout: 30), "Reverting did not finish")
    }
}
