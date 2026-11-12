import Foundation

/// How the clock written in a filename should be read.
public enum FilenameClock: String, Codable, Hashable, Sendable {
    /// Wall-clock time where the photo was taken, read in the time zone the user works in.
    case local
    /// Coordinated universal time (Pixel, Skype, Facebook and other epoch-based names).
    case utc
}

/// A time of day as written in a filename.
public struct TimeOfDay: Hashable, Sendable {
    public var hour: Int
    public var minute: Int
    public var second: Int
    public var millisecond: Int

    public init(hour: Int, minute: Int, second: Int, millisecond: Int = 0) {
        self.hour = hour
        self.minute = minute
        self.second = second
        self.millisecond = millisecond
    }

    public var isValid: Bool {
        (0..<24).contains(hour) && (0..<60).contains(minute) && (0..<60).contains(second)
            && (0..<1000).contains(millisecond)
    }
}

/// The date (and maybe time) a filename claims, before it is placed in a time zone.
public struct FilenameDate: Hashable, Sendable {
    /// `FilenameFormat.id` of the format that recognized the name.
    public var formatID: String
    public var year: Int
    public var month: Int
    public var day: Int
    /// `nil` when the name only carries a date (WhatsApp, BlackBerry, …).
    public var time: TimeOfDay?
    public var clock: FilenameClock

    public init(formatID: String, year: Int, month: Int, day: Int, time: TimeOfDay?, clock: FilenameClock) {
        self.formatID = formatID
        self.year = year
        self.month = month
        self.day = day
        self.time = time
        self.clock = clock
    }

    public var hasTime: Bool { time != nil }

    /// Whether the name describes a real calendar day and clock time (not 30 February or 25:00).
    public var isValid: Bool {
        guard (1...12).contains(month), year > 0 else { return false }
        guard (1...Self.daysInMonth(year: year, month: month)).contains(day) else { return false }
        return time?.isValid ?? true
    }

    /// The moment this name describes.
    ///
    /// Local names are read in `timeZone`; UTC names in UTC. A name without a time of day keeps the
    /// wall-clock time of `keepingTimeOf` in `timeZone` (the user's rule: an unknown time stays as it was),
    /// or noon when there is nothing to keep. In a daylight-saving gap the calendar moves the time forward.
    public func resolved(in timeZone: TimeZone, keepingTimeOf fallback: Date?) -> Date? {
        guard isValid else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = clock == .utc ? .phtofxrUTC : timeZone
        var components = DateComponents(year: year, month: month, day: day)
        if let time {
            components.hour = time.hour
            components.minute = time.minute
            components.second = time.second
            components.nanosecond = time.millisecond * 1_000_000
        } else if let fallback {
            var local = Calendar(identifier: .gregorian)
            local.timeZone = timeZone
            let kept = local.dateComponents([.hour, .minute, .second, .nanosecond], from: fallback)
            components.hour = kept.hour
            components.minute = kept.minute
            components.second = kept.second
            components.nanosecond = kept.nanosecond
        } else {
            components.hour = 12
        }
        return calendar.date(from: components)
    }

    /// The date and time this name describes, written out in UTC.
    static func utc(formatID: String, epochSeconds: TimeInterval) -> FilenameDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .phtofxrUTC
        let date = Date(timeIntervalSince1970: epochSeconds)
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        let millisecond = Int((epochSeconds * 1000).rounded()) % 1000
        return FilenameDate(
            formatID: formatID,
            year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1,
            time: TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0, second: c.second ?? 0, millisecond: millisecond),
            clock: .utc
        )
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}

extension TimeZone {
    /// UTC, spelled the same on Apple platforms and Linux.
    static let phtofxrUTC = TimeZone(secondsFromGMT: 0)!
}
