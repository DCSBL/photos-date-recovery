import Foundation
import PhtofxrCore
import Testing
@testable import Phtofxr

/// The app model against the fixed fake library: permission, scan, keep/skip, apply and revert.
@MainActor
struct AppModelTests {
    private func makeModel(storage: URL? = nil) -> (AppModel, FakePhotoLibrary) {
        let suite = "phtofxr-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let library = FakePhotoLibrary()
        let storage = storage ?? temporaryStorage()
        return (AppModel(library: library, defaults: defaults, storage: storage), library)
    }

    private func temporaryStorage() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("phtofxr-tests-\(UUID().uuidString)")
    }

    @Test("A scan asks for access first, then fills every section")
    func scan() async {
        let (model, _) = makeModel()
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
        #expect(model.count(of: .changedByApp) == 0)
    }

    @Test("Review groups follow the import days, biggest first")
    func reviewGroups() async throws {
        let (model, _) = makeModel()
        await model.scan()
        let groups = model.groups(in: .review)
        let first = try #require(groups.first)
        #expect(first.day?.year == 2016 && first.day?.month == 10)
        #expect(first.certain.count >= 45)
        #expect(groups.flatMap(\.items).count == 95)
    }

    @Test("Leaving videos out removes them from the scan")
    func mediaKinds() async {
        let (model, _) = makeModel()
        model.setMediaKind(.video, included: false)
        await model.scan()
        #expect(model.item(id: "video") == nil)
        #expect(model.item(id: "screenshot") != nil)
    }

    @Test("Changing settings after a scan marks the result as stale")
    func staleResults() async throws {
        let (model, _) = makeModel()
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
        let storage = temporaryStorage()
        let first = AppModel(library: FakePhotoLibrary(), defaults: defaults, storage: storage)
        first.settings.minimumYear = 2001
        first.addsCaption = false
        let second = AppModel(library: FakePhotoLibrary(), defaults: defaults, storage: storage)
        #expect(second.settings.minimumYear == 2001)
        #expect(second.addsCaption == false)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("Keeping only accepts proposals; all certain ones become planned changes")
    func keep() async {
        let (model, _) = makeModel()
        await model.scan()
        model.keep(["reset-no-name", "correct", "conflict"])
        #expect(model.kept == ["conflict"])
        model.keep(model.certainIDs)
        #expect(model.plannedChanges.count == 94)
        model.unkeep(["conflict"])
        #expect(model.plannedChanges.count == 93)
    }

    @Test("Don't keep moves a proposal to Skipped, across scans, and back")
    func skip() async {
        let storage = temporaryStorage()
        let (model, _) = makeModel(storage: storage)
        await model.scan()
        model.keep(["conflict"])
        await model.skip(["conflict"]).value
        #expect(model.count(of: .skipped) == 1)
        #expect(model.count(of: .review) == 94)
        #expect(!model.isKept("conflict"))
        #expect(model.item(id: "conflict")?.proposedDate != nil)

        let (relaunched, _) = makeModel(storage: storage)
        await relaunched.scan()
        #expect(relaunched.count(of: .skipped) == 1)

        await relaunched.unskip(["conflict"]).value
        #expect(relaunched.count(of: .skipped) == 0)
        #expect(relaunched.count(of: .review) == 95)
    }

    @Test("Applying writes the journal, changes the dates, adds the caption line and can be reverted")
    func applyAndRevert() async throws {
        let (model, library) = makeModel()
        await model.scan()
        model.keep(model.certainIDs)
        let planned = model.plannedChanges
        let first = try #require(planned.first { $0.assetID == "import-11-0" })

        await model.applyKept()

        #expect(model.workState == .finished(changed: 93, failed: 0, reverted: false))
        #expect(model.kept.isEmpty)
        #expect(model.count(of: .changedByApp) == 93)
        #expect(model.count(of: .review) == 2)
        let changed = try #require(library.assets.first { $0.id == "import-11-0" })
        #expect(changed.creationDate == first.to)
        #expect(changed.addedDate == first.addedDate)
        let caption = try #require(library.captions["import-11-0"])
        #expect(caption.hasPrefix("Phtofxr: "))
        let batch = try #require(model.journalState.batches.first)
        #expect(batch.applied == 93)

        await model.revert(batch: batch.id)

        #expect(model.workState == .finished(changed: 93, failed: 0, reverted: true))
        #expect(model.count(of: .changedByApp) == 0)
        #expect(model.count(of: .review) == 95)
        let restored = try #require(library.assets.first { $0.id == "import-11-0" })
        #expect(restored.creationDate == first.from)
        #expect(library.captions["import-11-0"] == nil)
        #expect(model.journalState.batches.first?.isRevertable == false)
    }

    @Test("Without the caption option only the date changes")
    func applyWithoutCaption() async {
        let (model, library) = makeModel()
        model.addsCaption = false
        await model.scan()
        model.keep(["conflict"])
        await model.applyKept()
        #expect(model.workState == .finished(changed: 1, failed: 0, reverted: false))
        #expect(library.captions.isEmpty)
    }

    @Test("A picked date works without a date in the name, survives a relaunch and is applied like a proposal")
    func pickedDate() async throws {
        let storage = temporaryStorage()
        let (model, library) = makeModel(storage: storage)
        await model.scan()
        // IMG_0003.JPG was imported right after 2014-03-03 20.17.02.jpg.
        let id = "import-11-3"
        #expect(model.item(id: id)?.category == .noDateInName)
        let previous = try #require(model.previousPhotoDate(for: id))
        #expect(previous.id == "import-11-2")
        #expect(previous.date == model.item(id: "import-11-2")?.proposedDate)

        model.setManualDate(previous.date, for: id)
        #expect(model.isKept(id))
        let change = try #require(model.plannedChanges.first { $0.assetID == id })
        #expect(change.to == previous.date)
        #expect(change.formatID == PlannedChange.manualFormatID)

        let (relaunched, _) = makeModel(storage: storage)
        await relaunched.scan()
        #expect(relaunched.manualDates[id] == previous.date)
        #expect(relaunched.isKept(id))

        await model.applyKept()
        #expect(model.workState == .finished(changed: 1, failed: 0, reverted: false))
        #expect(model.manualDates.isEmpty)
        #expect(library.assets.first { $0.id == id }?.creationDate == previous.date)
        #expect(model.item(id: id)?.category == .changedByApp)
        #expect(!model.canPickDate(for: id))
    }

    @Test("A picked date wins over the proposal; undo keep or don't keep takes it away")
    func pickedDateOverProposal() async throws {
        let (model, _) = makeModel()
        await model.scan()
        let picked = Date(timeIntervalSince1970: 1_300_000_000)
        model.setManualDate(picked, for: "conflict")
        #expect(model.plannedChanges.first { $0.assetID == "conflict" }?.to == picked)
        let item = try #require(model.item(id: "conflict"))
        #expect(model.targetDate(of: item) == picked)

        model.unkeep(["conflict"])
        #expect(model.manualDates.isEmpty)
        #expect(model.plannedChanges.isEmpty)

        model.setManualDate(picked, for: "conflict")
        await model.skip(["conflict"]).value
        #expect(model.manualDates.isEmpty)
        #expect(!model.isKept("conflict"))
    }

    @Test("Imports can be looked up per section")
    func importLookup() async throws {
        let (model, _) = makeModel()
        await model.scan()
        let first = try #require(model.groups(in: .review).first)
        #expect(model.group(id: first.id, in: .review) == first)
        #expect(model.group(id: "1900-1-1", in: .review) == nil)
    }

    @Test("Nothing kept, nothing applied")
    func applyNothing() async {
        let (model, _) = makeModel()
        await model.scan()
        await model.applyKept()
        #expect(model.workState == .idle)
        #expect(model.journalState.batches.isEmpty)
    }
}
