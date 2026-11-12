import Foundation

/// One line of the change journal (PLAN.md §7). The journal is append-only: a change is written as `planned`
/// before PhotoKit is asked to make it, then as `applied` or `failed`, and later as `reverted`.
public struct JournalEntry: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Written before `performChanges`; without a follow-up the outcome is unknown until reconciled.
        case planned
        case applied
        case failed
        case reverted
    }

    public var kind: Kind
    /// The "apply" batch the change belongs to; a revert keeps the batch of the change it undoes.
    public var batchID: UUID
    public var assetID: String
    public var filename: String?
    /// The creation date before Phtofxr changed it; what a revert restores.
    public var oldCreationDate: Date?
    public var newCreationDate: Date
    public var addedDate: Date?
    /// The exact caption line Phtofxr added, so a revert removes only that line.
    public var captionLine: String?
    public var formatID: String?
    public var at: Date

    public init(
        kind: Kind,
        batchID: UUID,
        assetID: String,
        filename: String?,
        oldCreationDate: Date?,
        newCreationDate: Date,
        addedDate: Date?,
        captionLine: String?,
        formatID: String?,
        at: Date
    ) {
        self.kind = kind
        self.batchID = batchID
        self.assetID = assetID
        self.filename = filename
        self.oldCreationDate = oldCreationDate
        self.newCreationDate = newCreationDate
        self.addedDate = addedDate
        self.captionLine = captionLine
        self.formatID = formatID
        self.at = at
    }

    /// The same change with another outcome, written now.
    public func with(_ kind: Kind, at date: Date) -> JournalEntry {
        var copy = self
        copy.kind = kind
        copy.at = date
        return copy
    }
}

/// What the journal says about every photo and batch, folded from its entries in order.
public struct JournalState: Sendable {
    /// The latest entry per photo.
    public private(set) var latest: [String: JournalEntry] = [:]
    public private(set) var batches: [BatchSummary] = []

    public init(_ entries: [JournalEntry]) {
        var batchOrder: [UUID] = []
        var perBatch: [UUID: [String: JournalEntry]] = [:]
        var started: [UUID: Date] = [:]
        for entry in entries {
            latest[entry.assetID] = entry
            if perBatch[entry.batchID] == nil {
                batchOrder.append(entry.batchID)
                started[entry.batchID] = entry.at
            }
            perBatch[entry.batchID, default: [:]][entry.assetID] = entry
        }
        batches = batchOrder.reversed().map { id in
            let current = Array(perBatch[id, default: [:]].values)
            return BatchSummary(
                id: id,
                startedAt: started[id] ?? .distantPast,
                applied: current.filter { $0.kind == .applied }.count,
                failed: current.filter { $0.kind == .failed }.count,
                reverted: current.filter { $0.kind == .reverted }.count,
                unresolved: current.filter { $0.kind == .planned }.count
            )
        }
    }

    /// Photos whose current date was set by Phtofxr and not reverted.
    public var changedByApp: Set<String> {
        Set(latest.values.filter { $0.kind == .applied }.map(\.assetID))
    }

    /// Changes that were planned but never confirmed: the app stopped during `performChanges`.
    public var unresolved: [JournalEntry] {
        latest.values.filter { $0.kind == .planned }.sorted { $0.assetID < $1.assetID }
    }

    /// The applied changes of a batch that a revert would undo.
    public func revertable(in batch: UUID) -> [JournalEntry] {
        latest.values.filter { $0.batchID == batch && $0.kind == .applied }.sorted { $0.assetID < $1.assetID }
    }

    /// Settles unresolved changes against what the library shows now: if the photo carries the new date the
    /// change went through. A photo that is gone counts as failed.
    public static func reconcile(
        _ unresolved: [JournalEntry],
        currentCreationDates: [String: Date?],
        at date: Date = Date()
    ) -> [JournalEntry] {
        unresolved.map { entry in
            guard let current = currentCreationDates[entry.assetID] ?? nil else { return entry.with(.failed, at: date) }
            let applied = abs(current.timeIntervalSince(entry.newCreationDate)) < 1
            return entry.with(applied ? .applied : .failed, at: date)
        }
    }
}

/// One "apply" run as the history screen shows it.
public struct BatchSummary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let applied: Int
    public let failed: Int
    public let reverted: Int
    public let unresolved: Int

    public var isRevertable: Bool { applied > 0 }
}

/// The journal file: JSON Lines in Application Support, part of the normal device backup.
public final class JournalStore: @unchecked Sendable {
    // @unchecked: all access to the file goes through `lock`.
    public let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    /// Appends entries and flushes them to disk before returning.
    public func append(_ entries: [JournalEntry]) throws {
        guard !entries.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for entry in entries {
            data.append(try encoder.encode(entry))
            data.append(0x0A)
        }
        lock.lock()
        defer { lock.unlock() }
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) {
            _ = manager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if end > 0 {
            // A crash can leave a half-written last line; start on a fresh line so new entries stay readable.
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data([0x0A]) {
                data.insert(0x0A, at: data.startIndex)
            }
            try handle.seek(toOffset: end)
        }
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    /// Every entry in order. A line that does not decode (a write cut off by a crash) is skipped.
    public func load() throws -> [JournalEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(JournalEntry.self, from: Data(line))
        }
    }
}
