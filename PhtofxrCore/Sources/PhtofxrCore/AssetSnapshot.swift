import Foundation

/// The kinds of media the user can include in a scan.
public enum MediaKind: String, Codable, CaseIterable, Hashable, Sendable {
    case photo
    case video
    case screenshot
    case other
}

/// What the scan needs to know about one item in the photo library, copied out of PhotoKit.
public struct AssetSnapshot: Identifiable, Hashable, Sendable {
    /// `PHAsset.localIdentifier`.
    public let id: String
    /// Original filename, or `nil` when the library does not know one.
    public let filename: String?
    /// The "taken" date Photos shows and sorts on; the only date the app can change.
    public let creationDate: Date?
    /// When the item was added to the library. Read-only, so the original import date always survives.
    public let addedDate: Date?
    public let kind: MediaKind

    public init(id: String, filename: String?, creationDate: Date?, addedDate: Date?, kind: MediaKind) {
        self.id = id
        self.filename = filename
        self.creationDate = creationDate
        self.addedDate = addedDate
        self.kind = kind
    }
}
