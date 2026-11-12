import Foundation

/// The date of a nearby photo, for a photo whose own name says nothing.
///
/// Photos imported together arrive in the order of the folder they came from, so the photo added just before
/// one without a date was usually taken around the same time. Only photos whose date can be trusted count: a
/// date the user picked, a proposal from the name (certain or uncertain), or a date that is already correct.
public enum NeighborDate {
    public struct Match: Hashable, Sendable {
        public let id: String
        public let filename: String?
        public let date: Date
    }

    /// The nearest photo added before `id` on the same day that has a trusted date, or `nil`.
    public static func previous(
        to id: String,
        in items: [Classification],
        manualDates: [String: Date] = [:],
        timeZone: TimeZone
    ) -> Match? {
        guard let target = items.first(where: { $0.id == id }), let added = target.asset.addedDate else { return nil }
        let day = DayKey(added, in: timeZone)
        let sameImport = items
            .filter { $0.asset.addedDate.map { DayKey($0, in: timeZone) } == day }
            .sorted { lhs, rhs in
                let left = lhs.asset.addedDate ?? .distantPast
                let right = rhs.asset.addedDate ?? .distantPast
                if left != right { return left < right }
                return (lhs.asset.filename ?? lhs.id, lhs.id) < (rhs.asset.filename ?? rhs.id, rhs.id)
            }
        guard let position = sameImport.firstIndex(where: { $0.id == id }) else { return nil }
        for item in sameImport[..<position].reversed() {
            if let date = trustedDate(of: item, manualDates: manualDates) {
                return Match(id: item.id, filename: item.asset.filename, date: date)
            }
        }
        return nil
    }

    static func trustedDate(of item: Classification, manualDates: [String: Date]) -> Date? {
        if let manual = manualDates[item.id] { return manual }
        switch item.category {
        case .certain, .uncertain: return item.proposedDate
        case .alreadyCorrect, .changedByApp: return item.asset.creationDate
        case .suspicious, .noDateInName, .skipped: return nil
        }
    }
}
