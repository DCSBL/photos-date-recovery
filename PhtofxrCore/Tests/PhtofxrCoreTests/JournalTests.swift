import Foundation
import Testing
@testable import PhtofxrCore

@Suite("Change journal")
struct JournalTests {
    let batch = UUID()

    func entry(_ id: String, _ kind: JournalEntry.Kind, batch: UUID? = nil, new: Date = moment(2013, 1, 1)) -> JournalEntry {
        JournalEntry(
            kind: kind,
            batchID: batch ?? self.batch,
            assetID: id,
            filename: "\(id).jpg",
            oldCreationDate: moment(2016, 10, 11, 14, 0, 0),
            newCreationDate: new,
            addedDate: moment(2016, 10, 11, 14, 0, 0),
            captionLine: "Phtofxr: oorspronkelijke datum 11-10-2016 14:00",
            formatID: "android-camera",
            at: moment(2026, 11, 12)
        )
    }

    func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("phtofxr-journal-\(UUID().uuidString)")
            .appendingPathComponent("journal.jsonl")
    }

    @Test("Entries survive a round trip through the file, in order and to the millisecond")
    func roundTrip() throws {
        let store = JournalStore(url: temporaryURL())
        var first = entry("a", .planned)
        first.oldCreationDate = Date(timeIntervalSince1970: 1_476_194_400.123)
        try store.append([first, entry("b", .planned)])
        try store.append([first.with(.applied, at: moment(2026, 11, 12, 13))])
        let loaded = try store.load()
        #expect(loaded.map(\.assetID) == ["a", "b", "a"])
        #expect(loaded.map(\.kind) == [.planned, .planned, .applied])
        #expect(loaded.first?.oldCreationDate == first.oldCreationDate)
    }

    @Test("A missing file is an empty journal")
    func missingFile() throws {
        #expect(try JournalStore(url: temporaryURL()).load().isEmpty)
    }

    @Test("A torn last line is skipped, earlier lines survive")
    func tornLine() throws {
        let url = temporaryURL()
        let store = JournalStore(url: url)
        try store.append([entry("a", .applied)])
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"kind\":\"appl".utf8))
        try handle.close()
        let loaded = try store.load()
        #expect(loaded.map(\.assetID) == ["a"])
        // Appending after a torn line still works: the next entry starts on its own line.
        try store.append([entry("b", .applied)])
        #expect(try store.load().map(\.assetID) == ["a", "b"])
    }

    @Test("State follows the latest entry per photo")
    func state() {
        let state = JournalState([
            entry("a", .planned), entry("b", .planned), entry("c", .planned),
            entry("a", .applied), entry("b", .failed),
        ])
        #expect(state.changedByApp == ["a"])
        #expect(state.unresolved.map(\.assetID) == ["c"])
        #expect(state.revertable(in: batch).map(\.assetID) == ["a"])
        let summary = state.batches.first
        #expect(summary?.applied == 1)
        #expect(summary?.failed == 1)
        #expect(summary?.unresolved == 1)
        #expect(summary?.isRevertable == true)
    }

    @Test("A revert takes the photo out of 'changed by Phtofxr' and the batch is no longer revertable")
    func revert() {
        let state = JournalState([entry("a", .planned), entry("a", .applied), entry("a", .reverted)])
        #expect(state.changedByApp.isEmpty)
        #expect(state.revertable(in: batch).isEmpty)
        #expect(state.batches.first?.reverted == 1)
        #expect(state.batches.first?.isRevertable == false)
    }

    @Test("Batches are listed newest first; a photo changed again later belongs to the newer batch")
    func batches() {
        let older = UUID()
        let newer = UUID()
        let state = JournalState([
            entry("a", .applied, batch: older),
            entry("a", .reverted, batch: older),
            entry("a", .applied, batch: newer, new: moment(2014, 1, 1)),
        ])
        #expect(state.batches.map(\.id) == [newer, older])
        #expect(state.changedByApp == ["a"])
        #expect(state.revertable(in: older).isEmpty)
        #expect(state.revertable(in: newer).map(\.assetID) == ["a"])
    }

    @Test("Reconciling unresolved changes against the library")
    func reconcile() {
        let new = moment(2013, 1, 1)
        let unresolved = [entry("went-through", .planned), entry("did-not", .planned), entry("gone", .planned)]
        let settled = JournalState.reconcile(unresolved, currentCreationDates: [
            "went-through": new.addingTimeInterval(0.4),
            "did-not": moment(2016, 10, 11, 14, 0, 0),
        ])
        #expect(settled.map(\.kind) == [.applied, .failed, .failed])
    }
}

@Suite("Change planner")
struct ChangePlannerTests {
    func item(_ id: String, _ category: DateCategory, proposed: Date?, added: Date = moment(2016, 10, 11)) -> Classification {
        Classification(
            asset: snapshot("\(id).jpg", created: moment(2016, 10, 11, 14), added: added, id: id),
            category: category,
            filenameDate: nil,
            proposedDate: proposed,
            reasons: []
        )
    }

    @Test("Only kept, reviewable proposals become changes")
    func changes() {
        let items = [
            item("kept", .certain, proposed: moment(2013, 1, 1)),
            item("kept-uncertain", .uncertain, proposed: moment(2014, 1, 1)),
            item("not-kept", .certain, proposed: moment(2013, 2, 2)),
            item("kept-but-correct", .alreadyCorrect, proposed: nil),
            item("kept-but-skipped", .skipped, proposed: moment(2013, 3, 3)),
        ]
        let changes = ChangePlanner.changes(for: items, keeping: ["kept", "kept-uncertain", "kept-but-correct", "kept-but-skipped"])
        #expect(changes.map(\.assetID) == ["kept", "kept-uncertain"])
        #expect(changes.first?.from == moment(2016, 10, 11, 14))
        #expect(changes.first?.to == moment(2013, 1, 1))
    }

    @Test("Summary per import day, biggest first")
    func summary() {
        let items = [
            item("a", .certain, proposed: moment(2013, 1, 1), added: moment(2016, 10, 11)),
            item("b", .certain, proposed: moment(2015, 5, 5), added: moment(2016, 10, 11)),
            item("c", .certain, proposed: moment(2014, 1, 1), added: moment(2016, 10, 12)),
        ]
        let changes = ChangePlanner.changes(for: items, keeping: ["a", "b", "c"])
        let summary = ChangePlanner.summary(of: changes, timeZone: amsterdam)
        #expect(summary.map(\.count) == [2, 1])
        #expect(summary.first?.day == DayKey(year: 2016, month: 10, day: 11))
        #expect(summary.first?.earliest == moment(2013, 1, 1))
        #expect(summary.first?.latest == moment(2015, 5, 5))
    }

    @Test("Chunks keep order and size")
    func chunks() {
        #expect(ChangePlanner.chunks(Array(1...5), size: 2) == [[1, 2], [3, 4], [5]])
        #expect(ChangePlanner.chunks(Array(1...3), size: 10) == [[1, 2, 3]])
        #expect(ChangePlanner.chunks([Int](), size: 10).isEmpty)
        #expect(ChangePlanner.chunks([1, 2], size: 0) == [[1, 2]])
    }

    @Test("Planned journal entries carry the old date and the caption line")
    func plannedEntries() {
        let changes = ChangePlanner.changes(for: [item("a", .certain, proposed: moment(2013, 1, 1))], keeping: ["a"])
        let batch = UUID()
        let entries = ChangePlanner.plannedEntries(for: changes, batchID: batch, captionLines: ["a": "Phtofxr: x"], at: moment(2026, 11, 12))
        #expect(entries.count == 1)
        #expect(entries.first?.kind == .planned)
        #expect(entries.first?.batchID == batch)
        #expect(entries.first?.oldCreationDate == moment(2016, 10, 11, 14))
        #expect(entries.first?.captionLine == "Phtofxr: x")
    }
}

@Suite("Caption editor")
struct CaptionEditorTests {
    let line = "Phtofxr: oorspronkelijke datum 11-10-2016 14:00"

    @Test("Adding to an empty caption")
    func addToEmpty() {
        #expect(CaptionEditor.adding(line, to: nil) == line)
        #expect(CaptionEditor.adding(line, to: "") == line)
    }

    @Test("Adding keeps the user's caption and puts the line below it")
    func addToExisting() {
        #expect(CaptionEditor.adding(line, to: "Oma's verjaardag") == "Oma's verjaardag\n\(line)")
    }

    @Test("Adding twice does not duplicate the line")
    func addTwice() {
        let once = CaptionEditor.adding(line, to: "Oma")
        #expect(CaptionEditor.adding(line, to: once) == once)
    }

    @Test("Removing takes out only Phtofxr's line")
    func remove() {
        #expect(CaptionEditor.removing(line, from: "Oma's verjaardag\n\(line)") == "Oma's verjaardag")
        #expect(CaptionEditor.removing(line, from: line) == nil)
        #expect(CaptionEditor.removing(line, from: "Iets anders") == "Iets anders")
        #expect(CaptionEditor.removing(line, from: nil) == nil)
    }

    @Test("Removing still works after the user edited the caption around the line")
    func removeAfterEdit() {
        let edited = "Nieuwe titel\n\(line)\nNog een regel"
        #expect(CaptionEditor.removing(line, from: edited) == "Nieuwe titel\nNog een regel")
    }
}

@Suite("JSON file store")
struct JSONFileStoreTests {
    @Test("Saves and loads a set of skipped photos")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phtofxr-store-\(UUID().uuidString)")
            .appendingPathComponent("skipped.json")
        let store = JSONFileStore<Set<String>>(url: url)
        #expect(store.load() == nil)
        try store.save(["a", "b"])
        #expect(store.load() == ["a", "b"])
        try store.save([])
        #expect(store.load() == [])
    }
}

@Suite("Skipping proposals")
struct SkipOverlayTests {
    @Test("Only proposals move to skipped, and keep their proposed date")
    func overlay() {
        let classified = Classifier(timeZone: amsterdam, now: moment(2026, 11, 12)).classify([
            snapshot("IMG_20130101_101500.jpg", created: moment(2016, 10, 11, 14), added: moment(2016, 10, 11, 14), id: "proposal"),
            snapshot("IMG_1234.JPG", created: moment(2016, 10, 11, 14), id: "no-date"),
        ])
        let overlaid = Classification.applying(skipped: ["proposal", "no-date"], to: classified)
        let proposal = overlaid.first { $0.id == "proposal" }
        #expect(proposal?.category == .skipped)
        #expect(proposal?.proposedDate == moment(2013, 1, 1, 10, 15, 0))
        #expect(overlaid.first { $0.id == "no-date" }?.category == .noDateInName)
        #expect(Classification.applying(skipped: [], to: classified) == classified)
    }
}

@Suite("Dates picked by the user")
struct ManualDateTests {
    func item(_ id: String, _ category: DateCategory, proposed: Date?) -> Classification {
        Classification(
            asset: snapshot("\(id).jpg", created: moment(2016, 10, 11, 14), added: moment(2016, 10, 11), id: id),
            category: category,
            filenameDate: nil,
            proposedDate: proposed,
            reasons: []
        )
    }

    @Test("A picked date works for any photo and wins over the proposal")
    func manual() {
        let items = [
            item("no-date", .noDateInName, proposed: nil),
            item("proposal", .certain, proposed: moment(2013, 1, 1)),
            item("changed", .changedByApp, proposed: nil),
            item("not-kept", .noDateInName, proposed: nil),
        ]
        let picked = moment(2005, 6, 7, 8, 9, 10)
        let changes = ChangePlanner.changes(
            for: items,
            keeping: ["no-date", "proposal", "changed"],
            manualDates: ["no-date": picked, "proposal": moment(2014, 2, 2), "changed": picked, "not-kept": picked]
        )
        #expect(changes.map(\.assetID) == ["no-date", "proposal"])
        #expect(changes.first?.to == picked)
        #expect(changes.first?.formatID == PlannedChange.manualFormatID)
        #expect(changes.last?.to == moment(2014, 2, 2))
    }
}

@Suite("Date of the previous photo in an import")
struct NeighborDateTests {
    func item(_ id: String, _ category: DateCategory, added: Date, created: Date = moment(2016, 10, 11, 14), proposed: Date? = nil) -> Classification {
        Classification(
            asset: snapshot("\(id).jpg", created: created, added: added, id: id),
            category: category,
            filenameDate: nil,
            proposedDate: proposed,
            reasons: []
        )
    }

    let items: [Classification] = [
        // Out of order on purpose: the order that counts is the order of adding.
        item("d-no-name", .noDateInName, added: moment(2016, 10, 11, 14, 0, 30)),
        item("a-proposal", .certain, added: moment(2016, 10, 11, 14, 0, 0), proposed: moment(2013, 1, 1)),
        item("c-suspicious", .suspicious, added: moment(2016, 10, 11, 14, 0, 20)),
        item("b-skipped", .skipped, added: moment(2016, 10, 11, 14, 0, 10), proposed: moment(2013, 2, 2)),
        item("e-other-day", .certain, added: moment(2016, 10, 12, 9), proposed: moment(2014, 1, 1)),
        item("f-no-name-next-day", .noDateInName, added: moment(2016, 10, 12, 10)),
        item("g-first", .noDateInName, added: moment(2016, 10, 13, 10)),
    ]

    @Test("Skips photos without a trusted date and stays within the import day")
    func previous() {
        let match = NeighborDate.previous(to: "d-no-name", in: items, timeZone: amsterdam)
        #expect(match?.id == "a-proposal")
        #expect(match?.date == moment(2013, 1, 1))
        #expect(NeighborDate.previous(to: "f-no-name-next-day", in: items, timeZone: amsterdam)?.id == "e-other-day")
        #expect(NeighborDate.previous(to: "g-first", in: items, timeZone: amsterdam) == nil)
        #expect(NeighborDate.previous(to: "missing", in: items, timeZone: amsterdam) == nil)
    }

    @Test("A date the user picked counts, also for a photo without a date in its name")
    func manual() {
        let picked = moment(2012, 12, 24, 20)
        let match = NeighborDate.previous(to: "d-no-name", in: items, manualDates: ["c-suspicious": picked], timeZone: amsterdam)
        #expect(match?.id == "c-suspicious")
        #expect(match?.date == picked)
    }
}
