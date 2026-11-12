import Foundation

/// Photos added to the library on the same day: one import, usually.
public struct ImportGroup: Identifiable, Hashable, Sendable {
    /// `nil` collects photos without an added date.
    public let day: DayKey?
    /// Sorted by proposed date, then current creation date, then filename.
    public let items: [Classification]

    public var id: String {
        guard let day else { return "unknown" }
        return "\(day.year)-\(day.month)-\(day.day)"
    }

    public var certain: [Classification] { items.filter { $0.category == .certain } }
    public var uncertain: [Classification] { items.filter { $0.category == .uncertain } }
}

public enum ImportGrouping {
    public enum Order: String, CaseIterable, Codable, Sendable {
        /// Biggest imports first: where the trouble usually is.
        case largestFirst
        case newestFirst
        case oldestFirst
    }

    public static func groups(
        _ items: [Classification],
        timeZone: TimeZone,
        order: Order = .largestFirst
    ) -> [ImportGroup] {
        var byDay: [DayKey?: [Classification]] = [:]
        for item in items {
            byDay[item.asset.addedDate.map { DayKey($0, in: timeZone) }, default: []].append(item)
        }
        let groups = byDay.map { day, items in ImportGroup(day: day, items: items.sorted(by: itemOrder)) }
        return groups.sorted { lhs, rhs in
            // Photos without an added date always go last.
            guard let left = lhs.day else { return false }
            guard let right = rhs.day else { return true }
            switch order {
            case .largestFirst:
                return lhs.items.count != rhs.items.count ? lhs.items.count > rhs.items.count : left > right
            case .newestFirst:
                return left > right
            case .oldestFirst:
                return left < right
            }
        }
    }

    private static func itemOrder(_ lhs: Classification, _ rhs: Classification) -> Bool {
        let left = lhs.proposedDate ?? lhs.asset.creationDate ?? .distantPast
        let right = rhs.proposedDate ?? rhs.asset.creationDate ?? .distantPast
        if left != right { return left < right }
        return (lhs.asset.filename ?? lhs.id) < (rhs.asset.filename ?? rhs.id)
    }
}
