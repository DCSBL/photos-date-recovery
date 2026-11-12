import Foundation
import PhtofxrCore
import Testing
@testable import Phtofxr

/// The app model against the fixed fake library: permission, scan and the section counts.
@MainActor
struct AppModelTests {
    private func makeModel() -> AppModel {
        let suite = "phtofxr-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppModel(library: FakePhotoLibrary(), defaults: defaults)
    }

    @Test("A scan asks for access first, then fills every section")
    func scan() async {
        let model = makeModel()
        #expect(model.access == .notDetermined)
        #expect(!model.hasResults)

        await model.scan()

        #expect(model.access == .full)
        #expect(model.hasResults)
        // 2 import days × 45 dated names, plus the reset-date photo, the video and the screenshot.
        #expect(model.counts[.certain] == 93)
        #expect(model.counts[.uncertain] == 2)
        #expect(model.count(of: .review) == 95)
        #expect(model.count(of: .suspicious) == 2)
        #expect(model.count(of: .alreadyCorrect) == 1)
        #expect(model.count(of: .noDateInName) == 30)
        #expect(model.count(of: .skipped) == 0)
    }

    @Test("Review groups follow the import days, biggest first")
    func reviewGroups() async throws {
        let model = makeModel()
        await model.scan()
        let groups = model.groups(in: .review)
        let first = try #require(groups.first)
        #expect(first.day?.year == 2016 && first.day?.month == 10)
        #expect(first.certain.count >= 45)
        #expect(groups.flatMap(\.items).count == 95)
    }

    @Test("Leaving videos out removes them from the scan")
    func mediaKinds() async {
        let model = makeModel()
        model.setMediaKind(.video, included: false)
        await model.scan()
        #expect(model.item(id: "video") == nil)
        #expect(model.item(id: "screenshot") != nil)
    }

    @Test("Changing settings after a scan marks the result as stale")
    func staleResults() async throws {
        let model = makeModel()
        await model.scan()
        #expect(!model.resultsAreStale)
        let whatsapp = try #require(FilenameFormat.catalog.first { $0.id == "whatsapp" })
        model.setFormat(whatsapp, enabled: false)
        #expect(model.resultsAreStale)
        #expect(model.settings.formatOverrides["whatsapp"] == false)
        model.setFormat(whatsapp, enabled: true)
        #expect(model.settings.formatOverrides["whatsapp"] == nil)
    }

    @Test("Settings survive a relaunch")
    func settingsPersist() {
        let suite = "phtofxr-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let first = AppModel(library: FakePhotoLibrary(), defaults: defaults)
        first.settings.minimumYear = 2001
        let second = AppModel(library: FakePhotoLibrary(), defaults: defaults)
        #expect(second.settings.minimumYear == 2001)
        defaults.removePersistentDomain(forName: suite)
    }
}
