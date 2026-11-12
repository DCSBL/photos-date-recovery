import Foundation

/// The user's choices for a scan. Every threshold has the default agreed in PLAN.md.
public struct RecoverySettings: Codable, Hashable, Sendable {
    /// Below this difference the photo already has the right date.
    public var alreadyCorrectWithin: TimeInterval
    /// Up to this difference a proposal is uncertain (a day or a week off).
    public var uncertainWithin: TimeInterval
    /// Names that claim an earlier year are suspicious; so are creation dates before it.
    public var minimumYear: Int
    /// A creation date within this span of the added date was probably filled in at import.
    public var addedDateNearness: TimeInterval
    /// A day with at least this many photos can be a pile day (a bulk import that got one date).
    public var pileDayMinimumCount: Int
    /// …when at least this share of its photos has a name date far away.
    public var pileDayMinimumShare: Double
    /// Formats switched away from their default, by `FilenameFormat.id`. New formats keep their own default.
    public var formatOverrides: [String: Bool]
    public var mediaKinds: Set<MediaKind>

    public init(
        alreadyCorrectWithin: TimeInterval = 24 * 3600,
        uncertainWithin: TimeInterval = 7 * 24 * 3600,
        minimumYear: Int = 1995,
        addedDateNearness: TimeInterval = 24 * 3600,
        pileDayMinimumCount: Int = 50,
        pileDayMinimumShare: Double = 0.5,
        formatOverrides: [String: Bool] = [:],
        mediaKinds: Set<MediaKind> = [.photo, .video, .screenshot]
    ) {
        self.alreadyCorrectWithin = alreadyCorrectWithin
        self.uncertainWithin = uncertainWithin
        self.minimumYear = minimumYear
        self.addedDateNearness = addedDateNearness
        self.pileDayMinimumCount = pileDayMinimumCount
        self.pileDayMinimumShare = pileDayMinimumShare
        self.formatOverrides = formatOverrides
        self.mediaKinds = mediaKinds
    }

    public func isEnabled(_ format: FilenameFormat) -> Bool {
        formatOverrides[format.id] ?? format.isEnabledByDefault
    }

    public var enabledFormats: [FilenameFormat] {
        FilenameFormat.catalog.filter(isEnabled)
    }
}
