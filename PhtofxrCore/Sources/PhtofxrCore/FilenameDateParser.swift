import Foundation

/// Reads the date a filename claims, using the formats that are switched on.
///
/// The first format in catalog order that matches wins. A match with an impossible date
/// (`IMG_20170230_120000`) is still returned so the scan can flag it; check `FilenameDate.isValid`.
public final class FilenameDateParser: @unchecked Sendable {
    // @unchecked: only immutable state; NSRegularExpression is safe to share between threads.
    private struct Compiled {
        let format: FilenameFormat
        let regex: NSRegularExpression
        let fields: [FilenameFormat.Field]
    }

    private let compiled: [Compiled]

    /// - Parameter formats: The formats to try, in order. Defaults to every format that is on by default.
    public init(formats: [FilenameFormat] = FilenameFormat.catalog.filter(\.isEnabledByDefault)) {
        compiled = formats.flatMap { format in
            format.patterns.map { pattern in
                // The catalog is fixed and covered by tests, so a broken pattern is a programming error.
                let regex = try! NSRegularExpression(pattern: pattern.regex, options: [.caseInsensitive])
                return Compiled(format: format, regex: regex, fields: pattern.fields)
            }
        }
    }

    public func parse(_ filename: String) -> FilenameDate? {
        // Every format needs at least six digits; most names without a date (IMG_1234) stop here.
        guard filename.utf8.lazy.filter({ $0 >= 0x30 && $0 <= 0x39 }).count >= 6 else { return nil }
        let range = NSRange(filename.startIndex..., in: filename)
        for entry in compiled {
            guard let match = entry.regex.firstMatch(in: filename, options: [], range: range) else { continue }
            if let date = Self.date(from: match, in: filename, fields: entry.fields, format: entry.format) {
                return date
            }
        }
        return nil
    }

    private static func date(
        from match: NSTextCheckingResult,
        in filename: String,
        fields: [FilenameFormat.Field],
        format: FilenameFormat
    ) -> FilenameDate? {
        var values: [FilenameFormat.Field: String] = [:]
        var spans: [DateSpan] = []
        for (offset, field) in fields.enumerated() {
            let groupRange = match.range(at: offset + 1)
            guard groupRange.location != NSNotFound, let range = Range(groupRange, in: filename) else { continue }
            values[field] = String(filename[range])
            if let part = Self.part(for: field) {
                spans.append(DateSpan(part: part, utf16Range: groupRange.location..<(groupRange.location + groupRange.length)))
            }
        }
        spans.sort { $0.utf16Range.lowerBound < $1.utf16Range.lowerBound }

        if let millis = values[.epochMilliseconds].flatMap(Double.init) {
            return .utc(formatID: format.id, epochSeconds: millis / 1000)
        }
        if let seconds = values[.epochSeconds].flatMap(Double.init) {
            return .utc(formatID: format.id, epochSeconds: seconds)
        }

        guard let year = values[.year].flatMap(Int.init),
              let month = values[.month].flatMap(Int.init),
              let day = values[.day].flatMap(Int.init)
        else { return nil }

        var time: TimeOfDay?
        if let hour = values[.hour].flatMap(Int.init),
           let minute = values[.minute].flatMap(Int.init),
           let second = values[.second].flatMap(Int.init) {
            let millisecond = values[.millisecond].flatMap(Int.init) ?? 0
            time = TimeOfDay(
                hour: to24Hour(hour, meridiem: values[.meridiem]),
                minute: minute,
                second: second,
                millisecond: millisecond
            )
        }
        return FilenameDate(formatID: format.id, year: year, month: month, day: day, time: time, clock: format.clock, spans: spans)
    }

    private static func part(for field: FilenameFormat.Field) -> DateSpan.Part? {
        switch field {
        case .year: .year
        case .month: .month
        case .day: .day
        case .hour, .meridiem: .hour
        case .minute: .minute
        case .second: .second
        case .millisecond: .fraction
        case .epochSeconds, .epochMilliseconds: nil
        }
    }

    /// 12 AM is midnight, 12 PM is noon. Out-of-range hours are left alone so the date reads as invalid.
    static func to24Hour(_ hour: Int, meridiem: String?) -> Int {
        guard let meridiem = meridiem?.uppercased(), (1...12).contains(hour) else { return hour }
        switch meridiem {
        case "AM": return hour == 12 ? 0 : hour
        case "PM": return hour == 12 ? 12 : hour + 12
        default: return hour
        }
    }
}
