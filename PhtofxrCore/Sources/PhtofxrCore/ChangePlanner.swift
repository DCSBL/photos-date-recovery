import Foundation

/// One date change as the review screen shows it and the journal records it.
public struct PlannedChange: Identifiable, Hashable, Sendable {
    public var id: String { assetID }
    public let assetID: String
    public let filename: String?
    public let from: Date?
    public let to: Date
    public let addedDate: Date?
    public let formatID: String?

    public init(assetID: String, filename: String?, from: Date?, to: Date, addedDate: Date?, formatID: String?) {
        self.assetID = assetID
        self.filename = filename
        self.from = from
        self.to = to
        self.addedDate = addedDate
        self.formatID = formatID
    }
}

/// What PhotoKit is asked to do for one photo: a new creation date, and optionally a caption line to add or remove.
public struct DateEdit: Hashable, Sendable {
    public let assetID: String
    public let newCreationDate: Date
    public let captionLineToAdd: String?
    public let captionLineToRemove: String?

    public init(assetID: String, newCreationDate: Date, captionLineToAdd: String? = nil, captionLineToRemove: String? = nil) {
        self.assetID = assetID
        self.newCreationDate = newCreationDate
        self.captionLineToAdd = captionLineToAdd
        self.captionLineToRemove = captionLineToRemove
    }
}

/// The review screen's summary of one import: how many photos and the range of their new dates.
public struct ImportSummary: Identifiable, Hashable, Sendable {
    public var id: String { day.map { "\($0.year)-\($0.month)-\($0.day)" } ?? "unknown" }
    public let day: DayKey?
    public let count: Int
    public let earliest: Date
    public let latest: Date
}

public enum ChangePlanner {
    /// The changes for the proposals the user chose to keep. Only reviewable items with a proposed date qualify.
    public static func changes(for items: [Classification], keeping keep: Set<String>) -> [PlannedChange] {
        items.compactMap { item in
            guard keep.contains(item.id), item.category.isReviewable, let to = item.proposedDate else { return nil }
            return PlannedChange(
                assetID: item.id,
                filename: item.asset.filename,
                from: item.asset.creationDate,
                to: to,
                addedDate: item.asset.addedDate,
                formatID: item.filenameDate?.formatID
            )
        }
        .sorted { ($0.addedDate ?? .distantPast, $0.assetID) < ($1.addedDate ?? .distantPast, $1.assetID) }
    }

    /// Per import day, biggest first, for the review screen.
    public static func summary(of changes: [PlannedChange], timeZone: TimeZone) -> [ImportSummary] {
        let byDay = Dictionary(grouping: changes) { change in change.addedDate.map { DayKey($0, in: timeZone) } }
        return byDay.map { day, changes in
            let dates = changes.map(\.to)
            return ImportSummary(day: day, count: changes.count, earliest: dates.min() ?? .distantPast, latest: dates.max() ?? .distantPast)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return (lhs.day ?? DayKey(year: 0, month: 0, day: 0)) > (rhs.day ?? DayKey(year: 0, month: 0, day: 0))
        }
    }

    /// Splits work into blocks: iOS asks for permission once per `performChanges`, so blocks stay large.
    public static func chunks<T>(_ items: [T], size: Int) -> [[T]] {
        guard size > 0, !items.isEmpty else { return items.isEmpty ? [] : [items] }
        return stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }

    /// Journal entries for a batch, written before PhotoKit is asked to change anything.
    public static func plannedEntries(
        for changes: [PlannedChange],
        batchID: UUID,
        captionLines: [String: String],
        at date: Date
    ) -> [JournalEntry] {
        changes.map { change in
            JournalEntry(
                kind: .planned,
                batchID: batchID,
                assetID: change.assetID,
                filename: change.filename,
                oldCreationDate: change.from,
                newCreationDate: change.to,
                addedDate: change.addedDate,
                captionLine: captionLines[change.assetID],
                formatID: change.formatID,
                at: date
            )
        }
    }
}

/// Adds and removes the single caption line Phtofxr writes, leaving whatever else the caption says alone.
public enum CaptionEditor {
    public static func adding(_ line: String, to caption: String?) -> String {
        let lines = split(caption)
        if lines.contains(line) { return lines.joined(separator: "\n") }
        return (lines + [line]).joined(separator: "\n")
    }

    /// `nil` when nothing else remains, which clears the caption.
    public static func removing(_ line: String, from caption: String?) -> String? {
        let remaining = split(caption).filter { $0 != line }
        return remaining.isEmpty ? nil : remaining.joined(separator: "\n")
    }

    private static func split(_ caption: String?) -> [String] {
        guard let caption else { return [] }
        return caption
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// A small Codable value in a JSON file, such as the photos the user chose not to keep.
public final class JSONFileStore<Value: Codable & Sendable>: @unchecked Sendable {
    // @unchecked: all file access goes through `lock`.
    public let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    public func load() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
