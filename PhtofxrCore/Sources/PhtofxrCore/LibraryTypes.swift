import Foundation

// Plain data the app passes between PhotoKit reading (off the main actor) and its screens. It lives here,
// outside the app's main-actor-by-default module, so background code can create it freely.

/// The app's photo library permission, simplified from `PHAuthorizationStatus`.
public enum LibraryAccess: Equatable, Sendable {
    case notDetermined
    case full
    /// The user shared only selected photos; the scan sees just those.
    case limited
    case denied
    case restricted

    public var canScan: Bool { self == .full || self == .limited }
}

/// Everything the diagnostics screen shows about one library item, straight from PhotoKit.
public struct AssetDiagnostics: Identifiable, Hashable, Sendable {
    public let id: String
    /// `PHAsset.extendedMetadata.originalFilename`.
    public let assetFilename: String?
    /// `PHAssetResource.filename` per resource, labelled with the resource type.
    public let resourceFilenames: [String]
    public let creationDate: Date?
    public let addedDate: Date?
    public let modificationDate: Date?
    public let caption: String?

    public init(
        id: String,
        assetFilename: String?,
        resourceFilenames: [String],
        creationDate: Date?,
        addedDate: Date?,
        modificationDate: Date?,
        caption: String?
    ) {
        self.id = id
        self.assetFilename = assetFilename
        self.resourceFilenames = resourceFilenames
        self.creationDate = creationDate
        self.addedDate = addedDate
        self.modificationDate = modificationDate
        self.caption = caption
    }
}

/// Checks of the PhotoKit assumptions (PLAN.md §8). Asset names and added dates are counted over the whole
/// library (as fast as a scan); resource names are slow to read, so they are compared on a spread-out sample.
public struct DiagnosticsReport: Hashable, Sendable {
    public var total = 0
    public var missingAssetFilename = 0
    public var missingAddedDate = 0
    /// How many photos the resource-name comparison looked at.
    public var sampleSize = 0
    public var missingResourceFilename = 0
    /// Asset-level and primary resource name both present but different, within the sample.
    public var differentFilenames = 0
    public var duration: Duration = .zero
    public var samples: [AssetDiagnostics] = []

    public init() {}
}

/// The result buckets as the sidebar shows them; "To review" holds both certain and uncertain proposals.
public enum ResultSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case review
    case suspicious
    case alreadyCorrect
    case noDateInName
    case skipped
    case changedByApp

    public var id: String { rawValue }

    public var categories: Set<DateCategory> {
        switch self {
        case .review: [.certain, .uncertain]
        case .suspicious: [.suspicious]
        case .alreadyCorrect: [.alreadyCorrect]
        case .noDateInName: [.noDateInName]
        case .skipped: [.skipped]
        case .changedByApp: [.changedByApp]
        }
    }

    /// The import groups of this section, biggest import first.
    public static func groups(_ classified: [Classification], timeZone: TimeZone) -> [ResultSection: [ImportGroup]] {
        var groups: [ResultSection: [ImportGroup]] = [:]
        for section in allCases {
            let items = classified.filter { section.categories.contains($0.category) }
            groups[section] = ImportGrouping.groups(items, timeZone: timeZone)
        }
        return groups
    }
}

extension Classification {
    /// The same proposal, set aside by the user ("don't keep"). The proposed date stays, so it can be restored.
    public func skippedByUser() -> Classification {
        Classification(asset: asset, category: .skipped, filenameDate: filenameDate, proposedDate: proposedDate, reasons: [.skippedByUser])
    }

    /// Applies the user's "don't keep" choices to a scan that was classified without them. Only proposals can be
    /// skipped; everything else keeps its category.
    public static func applying(skipped: Set<String>, to classified: [Classification]) -> [Classification] {
        guard !skipped.isEmpty else { return classified }
        return classified.map { item in
            item.category.isReviewable && skipped.contains(item.id) ? item.skippedByUser() : item
        }
    }
}
