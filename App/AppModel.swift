import Foundation
import Observation
import PhtofxrCore

/// App state: permission, scan settings and the latest scan result. Read-only towards the photo library.
@Observable
final class AppModel {
    enum ScanState: Equatable {
        case idle
        case scanning(progress: Double)
        case finished
    }

    let library: any PhotoLibraryClient
    let timeZone: TimeZone
    private let defaults: UserDefaults

    var access: LibraryAccess
    private(set) var scanState: ScanState = .idle
    var settings: RecoverySettings {
        didSet { saveSettings() }
    }
    /// Set when settings change after a scan, so the sidebar can suggest scanning again.
    private(set) var resultsAreStale = false

    private(set) var counts = CategoryCounts([])
    private(set) var lastScanDuration: Duration?
    private var byID: [String: Classification] = [:]
    private var groupsBySection: [ResultSection: [ImportGroup]] = [:]

    init(library: any PhotoLibraryClient, defaults: UserDefaults = .standard, timeZone: TimeZone = .current) {
        self.library = library
        self.defaults = defaults
        self.timeZone = timeZone
        access = library.currentAccess()
        settings = Self.loadSettings(from: defaults)
    }

    /// The model for this launch: PhotoKit normally, the fixed fake library under UI tests.
    static func forLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        #if DEBUG
        if arguments.contains("-phtofxrUITest") {
            let suite = "phtofxr-ui-test"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            return AppModel(library: FakePhotoLibrary(), defaults: defaults)
        }
        #endif
        return AppModel(library: LivePhotoLibrary())
    }

    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }

    var hasResults: Bool { scanState == .finished }

    func refreshAccess() {
        access = library.currentAccess()
    }

    /// Asks for permission when needed (just in time), then reads and classifies the library.
    func scan() async {
        guard !isScanning else { return }
        if access == .notDetermined { access = await library.requestAccess() }
        guard access.canScan else { return }

        scanState = .scanning(progress: 0)
        let clock = ContinuousClock()
        let start = clock.now
        let snapshots = await library.snapshots(kinds: settings.mediaKinds) { [weak self] fraction in
            Task { @MainActor in self?.updateProgress(fraction) }
        }
        let scanSettings = self.settings
        let zone = self.timeZone
        let classified = await Task.detached(priority: .userInitiated) {
            Classifier(settings: scanSettings, timeZone: zone).classify(snapshots)
        }.value
        let groups = await Task.detached(priority: .userInitiated) {
            ResultSection.groups(classified, timeZone: zone)
        }.value

        byID = Dictionary(classified.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        counts = CategoryCounts(classified)
        groupsBySection = groups
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

    func setMediaKind(_ kind: MediaKind, included: Bool) {
        if included { settings.mediaKinds.insert(kind) } else { settings.mediaKinds.remove(kind) }
    }

    func setFormat(_ format: FilenameFormat, enabled: Bool) {
        settings.formatOverrides[format.id] = enabled == format.isEnabledByDefault ? nil : enabled
    }

    // MARK: - Private

    private func updateProgress(_ fraction: Double) {
        if isScanning { scanState = .scanning(progress: fraction) }
    }

    private static let settingsKey = "settings.v1"

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
