import Foundation

/// The buckets a scan sorts photos into (PLAN.md §3).
public enum DateCategory: String, CaseIterable, Codable, Hashable, Sendable {
    /// The name date is far from a creation date that looks filled in: a confident proposal.
    case certain
    /// A proposal worth a look: a small difference, a clash with the photo's own date, or a shaky format.
    case uncertain
    /// The name claims an impossible date, or the photo carries a camera's reset date.
    case suspicious
    /// The creation date already agrees with the name.
    case alreadyCorrect
    case noDateInName
    /// The user chose "don't keep" in an earlier review.
    case skipped
    /// The change journal says this app already changed the date.
    case changedByApp

    /// Categories that hold a proposed date the user can accept.
    public var isReviewable: Bool { self == .certain || self == .uncertain }
}

/// Why a photo landed in its category; shown in the detail view.
public enum Reason: Hashable, Sendable {
    case noDateInName
    case invalidDateInName
    case nameBeforeMinimumYear
    case nameInFuture
    case missingCreationDate
    case matchesName
    case smallDifference
    case unreliableFormat
    /// The creation date is within a day of the added date: Photos filled it in at import.
    case nearAddedDate
    /// The creation date falls on a day where many photos' names point somewhere else.
    case pileDay(count: Int)
    /// The creation date looks like a camera whose clock was reset (1 January, early morning).
    case cameraResetDate
    /// The photo has its own date and the name disagrees with it.
    case conflictsWithOwnDate
    case skippedByUser
    case changedByApp
}

/// The verdict for one photo.
public struct Classification: Identifiable, Hashable, Sendable {
    public var id: String { asset.id }
    public let asset: AssetSnapshot
    public let category: DateCategory
    public let filenameDate: FilenameDate?
    /// The creation date the app would set; `nil` when there is nothing to propose.
    public let proposedDate: Date?
    public let reasons: [Reason]

    public init(asset: AssetSnapshot, category: DateCategory, filenameDate: FilenameDate?, proposedDate: Date?, reasons: [Reason]) {
        self.asset = asset
        self.category = category
        self.filenameDate = filenameDate
        self.proposedDate = proposedDate
        self.reasons = reasons
    }

    /// Proposed minus current creation date, in seconds.
    public var difference: TimeInterval? {
        guard let proposedDate, let creationDate = asset.creationDate else { return nil }
        return proposedDate.timeIntervalSince(creationDate)
    }
}

/// Sorts scanned photos into categories with a proposed date (PLAN.md §3).
public struct Classifier: Sendable {
    public let settings: RecoverySettings
    public let timeZone: TimeZone
    public let now: Date
    private let parser: FilenameDateParser

    public init(settings: RecoverySettings = RecoverySettings(), timeZone: TimeZone = .current, now: Date = Date()) {
        self.settings = settings
        self.timeZone = timeZone
        self.now = now
        parser = FilenameDateParser(formats: settings.enabledFormats)
    }

    /// - Parameters:
    ///   - skipped: Photos the user marked "don't keep" before.
    ///   - changedByApp: Photos the change journal lists as changed and not reverted.
    public func classify(
        _ assets: [AssetSnapshot],
        skipped: Set<String> = [],
        changedByApp: Set<String> = []
    ) -> [Classification] {
        let parsed = assets.map { asset in
            Parsed(asset: asset, name: asset.filename.flatMap(parser.parse))
        }
        let piles = pileDays(parsed)
        return parsed.map { classify($0, piles: piles, skipped: skipped, changedByApp: changedByApp) }
    }

    // MARK: - Steps

    private struct Parsed {
        let asset: AssetSnapshot
        let name: FilenameDate?

        func proposed(in timeZone: TimeZone) -> Date? {
            name?.resolved(in: timeZone, keepingTimeOf: asset.creationDate)
        }
    }

    /// Days (by creation date) with many photos whose names point far away: the shape of a bulk import
    /// that gave every file the same date.
    private func pileDays(_ parsed: [Parsed]) -> [DayKey: Int] {
        var total: [DayKey: Int] = [:]
        var farOff: [DayKey: Int] = [:]
        for item in parsed {
            guard let created = item.asset.creationDate else { continue }
            let day = DayKey(created, in: timeZone)
            total[day, default: 0] += 1
            if let proposed = item.proposed(in: timeZone), abs(proposed.timeIntervalSince(created)) > settings.uncertainWithin {
                farOff[day, default: 0] += 1
            }
        }
        var piles: [DayKey: Int] = [:]
        for (day, count) in total where count >= settings.pileDayMinimumCount {
            if Double(farOff[day] ?? 0) / Double(count) >= settings.pileDayMinimumShare {
                piles[day] = count
            }
        }
        return piles
    }

    private func classify(
        _ item: Parsed,
        piles: [DayKey: Int],
        skipped: Set<String>,
        changedByApp: Set<String>
    ) -> Classification {
        let asset = item.asset
        func result(_ category: DateCategory, _ reasons: [Reason], proposed: Date? = nil) -> Classification {
            Classification(asset: asset, category: category, filenameDate: item.name, proposedDate: proposed, reasons: reasons)
        }

        if changedByApp.contains(asset.id) { return result(.changedByApp, [.changedByApp]) }
        if skipped.contains(asset.id) { return result(.skipped, [.skippedByUser], proposed: item.proposed(in: timeZone)) }

        guard let name = item.name else {
            if let created = asset.creationDate, isCameraResetDate(created) {
                return result(.suspicious, [.noDateInName, .cameraResetDate])
            }
            return result(.noDateInName, [.noDateInName])
        }
        guard name.isValid, let proposed = item.proposed(in: timeZone) else {
            return result(.suspicious, [.invalidDateInName])
        }
        if name.year < settings.minimumYear { return result(.suspicious, [.nameBeforeMinimumYear]) }
        if proposed > now.addingTimeInterval(24 * 3600) { return result(.suspicious, [.nameInFuture]) }

        guard let created = asset.creationDate else {
            return result(.uncertain, [.missingCreationDate], proposed: proposed)
        }
        let difference = abs(proposed.timeIntervalSince(created))
        if difference < settings.alreadyCorrectWithin { return result(.alreadyCorrect, [.matchesName]) }

        let format = FilenameFormat.catalog.first { $0.id == name.formatID }
        if format?.isReliable == false { return result(.uncertain, [.unreliableFormat], proposed: proposed) }
        if difference <= settings.uncertainWithin { return result(.uncertain, [.smallDifference], proposed: proposed) }

        var fillIns: [Reason] = []
        if let added = asset.addedDate, abs(created.timeIntervalSince(added)) <= settings.addedDateNearness {
            fillIns.append(.nearAddedDate)
        }
        if let count = piles[DayKey(created, in: timeZone)] { fillIns.append(.pileDay(count: count)) }
        if isCameraResetDate(created) { fillIns.append(.cameraResetDate) }

        if fillIns.isEmpty { return result(.uncertain, [.conflictsWithOwnDate], proposed: proposed) }
        return result(.certain, fillIns, proposed: proposed)
    }

    /// 1 January before 06:00 in a year up to 2012, or any date before the minimum year: what cameras
    /// show after their clock battery ran out.
    func isCameraResetDate(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let year = c.year else { return false }
        if year < settings.minimumYear { return true }
        return c.month == 1 && c.day == 1 && (c.hour ?? 0) < 6 && year <= 2012
    }
}

/// How many photos are in each category.
public struct CategoryCounts: Hashable, Sendable {
    public private(set) var counts: [DateCategory: Int] = [:]

    public init(_ classifications: [Classification]) {
        for item in classifications { counts[item.category, default: 0] += 1 }
    }

    public subscript(category: DateCategory) -> Int { counts[category] ?? 0 }

    public var reviewable: Int { self[.certain] + self[.uncertain] }
}
