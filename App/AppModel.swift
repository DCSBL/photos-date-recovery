import Foundation
import Observation
import PhtofxrCore

/// App state: permission, scan settings, the latest scan, the user's keep/skip choices, and applying or
/// reverting changes through the journal (PLAN.md §5 and §7).
@Observable
final class AppModel {
    enum ScanState: Equatable {
        case idle
        case scanning(progress: Double)
        case finished
    }

    /// Applying or reverting dates. Both go through the journal first.
    enum WorkState: Equatable {
        case idle
        case applying(done: Int, total: Int)
        case reverting(done: Int, total: Int)
        case finished(changed: Int, failed: Int, reverted: Bool)
        case failed(String)
    }

    /// iOS asks for permission once per change block, so blocks are large (PLAN.md §2).
    static let blockSize = 1000

    let library: any PhotoLibraryClient
    let timeZone: TimeZone
    private let defaults: UserDefaults
    private let journal: JournalStore
    private let skippedStore: JSONFileStore<Set<String>>
    private let manualStore: JSONFileStore<[String: Date]>

    var access: LibraryAccess
    private(set) var scanState: ScanState = .idle
    var settings: RecoverySettings {
        didSet { saveSettings() }
    }
    /// Set when settings change after a scan, so the sidebar can suggest scanning again.
    private(set) var resultsAreStale = false

    private(set) var counts = CategoryCounts([])
    private(set) var lastScanDuration: Duration?
    /// The scan as classified, before the user's "don't keep" choices are laid over it.
    private var classified: [Classification] = []
    private var current: [Classification] = []
    private var byID: [String: Classification] = [:]
    private var groupsBySection: [ResultSection: [ImportGroup]] = [:]
    private var rebuildGeneration = 0

    /// Photos marked "keep", waiting for the review screen: proposals, and photos with a date the user picked.
    /// Proposals are not stored (one tap brings them back); picked dates are, together with their keep mark.
    private(set) var kept: Set<String> = []
    /// Dates the user picked for a photo ("Other date…"). They win over the proposal and count as kept.
    private(set) var manualDates: [String: Date]
    /// Proposals marked "don't keep"; stored so a new scan does not offer them again.
    private(set) var skipped: Set<String>
    private(set) var journalState: JournalState

    /// Whether applied changes also get a caption line with the original date (PLAN.md §7).
    var addsCaption: Bool {
        didSet { defaults.set(addsCaption, forKey: Self.captionKey) }
    }
    private(set) var workState: WorkState = .idle
    var isReviewing = false
    var isShowingHistory = false

    init(
        library: any PhotoLibraryClient,
        defaults: UserDefaults = .standard,
        storage: URL = AppModel.defaultStorage,
        timeZone: TimeZone = .current
    ) {
        self.library = library
        self.defaults = defaults
        self.timeZone = timeZone
        journal = JournalStore(url: storage.appendingPathComponent("journal.jsonl"))
        skippedStore = JSONFileStore(url: storage.appendingPathComponent("skipped.json"))
        manualStore = JSONFileStore(url: storage.appendingPathComponent("manual-dates.json"))
        access = library.currentAccess()
        settings = Self.loadSettings(from: defaults)
        skipped = skippedStore.load() ?? []
        manualDates = manualStore.load() ?? [:]
        kept = Set(manualDates.keys)
        journalState = JournalState((try? journal.load()) ?? [])
        addsCaption = defaults.object(forKey: Self.captionKey) as? Bool ?? true
    }

    /// Application Support/Phtofxr: included in the device backup, never synced anywhere by the app.
    static var defaultStorage: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Phtofxr", isDirectory: true)
    }

    /// The model for this launch: PhotoKit normally, the fixed fake library under UI tests.
    static func forLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        #if DEBUG
        if arguments.contains("-phtofxrUITest") {
            let suite = "phtofxr-ui-test"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            let storage = FileManager.default.temporaryDirectory.appendingPathComponent("phtofxr-ui-test-\(UUID().uuidString)")
            return AppModel(library: FakePhotoLibrary(), defaults: defaults, storage: storage)
        }
        #endif
        return AppModel(library: LivePhotoLibrary())
    }

    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }

    var isWorking: Bool {
        switch workState {
        case .applying, .reverting: true
        default: false
        }
    }

    var hasResults: Bool { scanState == .finished }

    func refreshAccess() {
        access = library.currentAccess()
    }

    // MARK: - Scanning

    /// Asks for permission when needed (just in time), then reads and classifies the library.
    func scan() async {
        guard !isScanning, !isWorking else { return }
        if access == .notDetermined { access = await library.requestAccess() }
        guard access.canScan else { return }

        scanState = .scanning(progress: 0)
        let clock = ContinuousClock()
        let start = clock.now
        let snapshots = await library.snapshots(kinds: settings.mediaKinds) { [weak self] fraction in
            Task { @MainActor in self?.updateProgress(fraction) }
        }
        reconcileJournal(with: snapshots)

        let scanSettings = self.settings
        let zone = self.timeZone
        let changed = journalState.changedByApp
        classified = await Task.detached(priority: .userInitiated) {
            Classifier(settings: scanSettings, timeZone: zone).classify(snapshots, changedByApp: changed)
        }.value
        await rebuild()
        lastScanDuration = start.duration(to: clock.now)
        resultsAreStale = false
        scanState = .finished
    }

    func groups(in section: ResultSection) -> [ImportGroup] {
        groupsBySection[section] ?? []
    }

    func count(of section: ResultSection) -> Int {
        section.categories.reduce(0) { $0 + counts[$1] }
    }

    func item(id: Classification.ID) -> Classification? {
        byID[id]
    }

    func group(id: ImportGroup.ID, in section: ResultSection) -> ImportGroup? {
        groupsBySection[section]?.first { $0.id == id }
    }

    func setMediaKind(_ kind: MediaKind, included: Bool) {
        if included { settings.mediaKinds.insert(kind) } else { settings.mediaKinds.remove(kind) }
    }

    func setFormat(_ format: FilenameFormat, enabled: Bool) {
        settings.formatOverrides[format.id] = enabled == format.isEnabledByDefault ? nil : enabled
    }

    // MARK: - Keep and skip

    func isKept(_ id: String) -> Bool { kept.contains(id) }

    /// Marks proposals to be applied. Only current proposals and photos with a picked date qualify.
    func keep<S: Sequence>(_ ids: S) where S.Element == String {
        kept.formUnion(ids.filter(isKeepable))
    }

    /// Takes back the keep mark, and a picked date with it.
    func unkeep<S: Sequence>(_ ids: S) where S.Element == String {
        let ids = Set(ids)
        kept.subtract(ids)
        removeManualDates(ids)
    }

    /// The date a photo gets when it is applied: the picked date, else the proposal.
    func targetDate(of item: Classification) -> Date? {
        manualDates[item.id] ?? item.proposedDate
    }

    // MARK: - Picking a date

    /// Whether the user can pick a date for this photo. Photos Phtofxr already changed are reverted first.
    func canPickDate(for id: String) -> Bool {
        guard let item = byID[id] else { return false }
        return item.category != .changedByApp
    }

    /// Sets the date the user picked and marks the photo as kept. Nothing changes until the review is confirmed.
    func setManualDate(_ date: Date, for id: String) {
        guard canPickDate(for: id) else { return }
        manualDates[id] = date
        kept.insert(id)
        saveManualDates()
    }

    /// The date of the photo added just before this one in the same import, for "Like the previous photo".
    func previousPhotoDate(for id: String) -> NeighborDate.Match? {
        NeighborDate.previous(to: id, in: current, manualDates: manualDates, timeZone: timeZone)
    }

    /// The date the filename describes, also when the scan did not propose it (suspicious, already correct).
    func nameDate(of item: Classification) -> Date? {
        item.proposedDate ?? item.filenameDate?.resolved(in: timeZone, keepingTimeOf: item.asset.creationDate)
    }

    /// Every certain proposal in the result, for the "keep all certain" action.
    var certainIDs: [String] {
        current.filter { $0.category == .certain }.map(\.id)
    }

    /// "Don't keep": the proposals move to Skipped and stay there across scans. The returned task finishes when
    /// the lists are rebuilt.
    @discardableResult
    func skip<S: Sequence>(_ ids: S) -> Task<Void, Never> where S.Element == String {
        let ids = Set(ids)
        kept.subtract(ids)
        removeManualDates(ids)
        skipped.formUnion(ids)
        saveSkipped()
        return Task { await rebuild() }
    }

    @discardableResult
    func unskip<S: Sequence>(_ ids: S) -> Task<Void, Never> where S.Element == String {
        skipped.subtract(ids)
        saveSkipped()
        return Task { await rebuild() }
    }

    // MARK: - Applying

    /// The changes the review screen shows and `applyKept` makes.
    var plannedChanges: [PlannedChange] {
        ChangePlanner.changes(for: current, keeping: kept, manualDates: manualDates)
    }

    /// The caption line for a change, in the app's language; the journal keeps the exact text for undo.
    func captionLine(for change: PlannedChange) -> String? {
        guard let from = change.from else { return nil }
        let style = Date.FormatStyle(timeZone: timeZone)
            .day(.twoDigits).month(.twoDigits).year(.defaultDigits)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return String(localized: "Phtofxr: original date \(from.formatted(style))")
    }

    /// Applies the kept proposals: journal first, then PhotoKit, block by block. Stops at the first block that
    /// fails (for example when the user declines the iOS prompt); earlier blocks stay applied and can be reverted.
    func applyKept() async {
        let changes = plannedChanges
        guard !changes.isEmpty, !isWorking, !isScanning else { return }
        let batchID = UUID()
        var lines: [String: String] = [:]
        if addsCaption {
            for change in changes {
                if let line = captionLine(for: change) { lines[change.assetID] = line }
            }
        }

        workState = .applying(done: 0, total: changes.count)
        var changedCount = 0
        var failedCount = 0
        var failure: String?
        for block in ChangePlanner.chunks(changes, size: Self.blockSize) {
            let planned = ChangePlanner.plannedEntries(for: block, batchID: batchID, captionLines: lines, at: Date())
            do {
                try journal.append(planned)
            } catch {
                // Without a journal entry there is no undo, so nothing is changed.
                failure = error.localizedDescription
                break
            }
            let edits = block.map { DateEdit(assetID: $0.assetID, newCreationDate: $0.to, captionLineToAdd: lines[$0.assetID]) }
            do {
                let done = try await library.apply(edits)
                try? journal.append(planned.map { $0.with(done.contains($0.assetID) ? .applied : .failed, at: Date()) })
                changedCount += done.count
                failedCount += block.count - done.count
            } catch {
                // A change block is all or nothing: none of this block changed.
                try? journal.append(planned.map { $0.with(.failed, at: Date()) })
                failedCount += block.count
                failure = error.localizedDescription
                break
            }
            workState = .applying(done: changedCount + failedCount, total: changes.count)
        }

        kept.removeAll()
        manualDates.removeAll()
        saveManualDates()
        reloadJournal()
        if let failure, changedCount == 0 {
            workState = .failed(failure)
        } else {
            workState = .finished(changed: changedCount, failed: failedCount, reverted: false)
        }
        await rescanAfterWork()
    }

    /// Puts back the original dates of a batch and removes Phtofxr's caption line. The added date was never touched.
    func revert(batch: UUID) async {
        let entries = journalState.revertable(in: batch)
        guard !entries.isEmpty, !isWorking, !isScanning else { return }
        workState = .reverting(done: 0, total: entries.count)
        var revertedCount = 0
        var failedCount = 0
        var failure: String?
        for block in ChangePlanner.chunks(entries, size: Self.blockSize) {
            let edits = block.compactMap { entry -> DateEdit? in
                guard let old = entry.oldCreationDate else { return nil }
                return DateEdit(assetID: entry.assetID, newCreationDate: old, captionLineToRemove: entry.captionLine)
            }
            do {
                let done = try await library.apply(edits)
                try? journal.append(block.filter { done.contains($0.assetID) }.map { $0.with(.reverted, at: Date()) })
                revertedCount += done.count
                failedCount += block.count - done.count
            } catch {
                failedCount += block.count
                failure = error.localizedDescription
                break
            }
            workState = .reverting(done: revertedCount + failedCount, total: entries.count)
        }
        reloadJournal()
        if let failure, revertedCount == 0 {
            workState = .failed(failure)
        } else {
            workState = .finished(changed: revertedCount, failed: failedCount, reverted: true)
        }
        await rescanAfterWork()
    }

    func acknowledgeWork() {
        if !isWorking { workState = .idle }
    }

    // MARK: - Private

    /// Lays the skip choices over the scan and rebuilds counts and groups off the main actor. Only the latest
    /// rebuild is kept when several overlap.
    private func rebuild() async {
        rebuildGeneration += 1
        let generation = rebuildGeneration
        let base = classified
        let skippedNow = skipped
        let zone = timeZone
        let (items, groups) = await Task.detached(priority: .userInitiated) {
            let items = Classification.applying(skipped: skippedNow, to: base)
            return (items, ResultSection.groups(items, timeZone: zone))
        }.value
        guard generation == rebuildGeneration else { return }
        current = items
        byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        counts = CategoryCounts(items)
        groupsBySection = groups
        // Photos that left the scan (deleted, or another media kind) or were changed meanwhile lose their choice.
        let stalePicks = Set(manualDates.keys.filter { byID[$0] == nil || byID[$0]?.category == .changedByApp })
        removeManualDates(stalePicks)
        kept = kept.filter(isKeepable)
    }

    private func isKeepable(_ id: String) -> Bool {
        guard let item = byID[id] else { return false }
        return item.category.isReviewable || (manualDates[id] != nil && item.category != .changedByApp)
    }

    private func removeManualDates(_ ids: Set<String>) {
        guard ids.contains(where: { manualDates[$0] != nil }) else { return }
        for id in ids { manualDates[id] = nil }
        saveManualDates()
    }

    private func rescanAfterWork() async {
        guard hasResults else { return }
        let state = workState
        await scan()
        workState = state
    }

    /// Settles changes that were planned but never confirmed (the app stopped mid-way), using what the
    /// library shows now. Photos outside this scan stay unresolved until a scan includes them.
    private func reconcileJournal(with snapshots: [AssetSnapshot]) {
        let unresolved = journalState.unresolved
        guard !unresolved.isEmpty else { return }
        let dates = Dictionary(snapshots.map { ($0.id, $0.creationDate) }, uniquingKeysWith: { first, _ in first })
        let present = unresolved.filter { dates[$0.assetID] != nil }
        try? journal.append(JournalState.reconcile(present, currentCreationDates: dates))
        reloadJournal()
    }

    private func reloadJournal() {
        journalState = JournalState((try? journal.load()) ?? [])
    }

    private func saveSkipped() {
        try? skippedStore.save(skipped)
    }

    private func saveManualDates() {
        try? manualStore.save(manualDates)
    }

    private func updateProgress(_ fraction: Double) {
        if isScanning { scanState = .scanning(progress: fraction) }
    }

    private static let settingsKey = "settings.v1"
    private static let captionKey = "addsCaption.v1"

    private static func loadSettings(from defaults: UserDefaults) -> RecoverySettings {
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(RecoverySettings.self, from: data)
        else { return RecoverySettings() }
        return settings
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
        if hasResults { resultsAreStale = true }
    }
}
