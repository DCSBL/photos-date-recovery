import PhtofxrCore
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Mark date parts with underline patterns instead of colors: the system's Differentiate Without Color, or
    /// the `-phtofxrWithoutColor` launch argument for screenshots.
    @Entry var marksDatePartsWithoutColor = false
}

/// One look per date part, the same in the filename and in the dates below it: year blue, month green, day red,
/// hours purple, minutes teal, seconds amber. Every color is readable on white and on black (contrast ≥ 4.5:1).
/// With Differentiate Without Color each part gets its own underline instead.
enum DatePartStyle {
    static func color(_ part: DateSpan.Part) -> Color {
        switch part {
        case .year: dynamic(light: 0x0A5CC2, dark: 0x64AEFF)
        case .month: dynamic(light: 0x167A3C, dark: 0x4FD07F)
        case .day: dynamic(light: 0xC42530, dark: 0xFF7B74)
        case .hour: dynamic(light: 0x7A3DC8, dark: 0xC6A0FF)
        case .minute: dynamic(light: 0x00707A, dark: 0x3FD0DB)
        case .second, .fraction: dynamic(light: 0x8A5300, dark: 0xF0B54A)
        }
    }

    static func underline(_ part: DateSpan.Part) -> Text.LineStyle {
        switch part {
        case .year: Text.LineStyle(pattern: .solid)
        case .month: Text.LineStyle(pattern: .dash)
        case .day: Text.LineStyle(pattern: .dot)
        case .hour: Text.LineStyle(pattern: .dashDot)
        case .minute: Text.LineStyle(pattern: .dashDotDot)
        case .second, .fraction: Text.LineStyle(pattern: .solid)
        }
    }

    /// The attributes for one part: bold, plus its color or its underline.
    static func mark(_ part: DateSpan.Part, withoutColor: Bool) -> AttributeContainer {
        var container = AttributeContainer()
        container.foundation.inlinePresentationIntent = .stronglyEmphasized
        if withoutColor {
            container.swiftUI.underlineStyle = underline(part)
        } else {
            container.swiftUI.foregroundColor = color(part)
        }
        return container
    }

    /// The filename with every date part marked.
    static func filename(_ name: String, spans: [DateSpan], withoutColor: Bool) -> AttributedString {
        var result = AttributedString()
        for segment in DateSpan.segments(of: name, spans: spans) {
            var piece = AttributedString(segment.text)
            if let part = segment.part {
                piece.mergeAttributes(mark(part, withoutColor: withoutColor))
            }
            result.append(piece)
        }
        return result
    }

    /// A date written out in the user's language, with the same marks on year, month, day and time.
    static func date(_ date: Date, style: Date.FormatStyle, withoutColor: Bool) -> AttributedString {
        var text = date.formatted(style.attributedStyle)
        let fields: [(AttributeScopes.FoundationAttributes.DateFieldAttribute.Value, DateSpan.Part)] = [
            (.year, .year), (.month, .month), (.day, .day),
            (.hour, .hour), (.amPM, .hour), (.minute, .minute),
            (.second, .second), (.secondFraction, .second),
        ]
        for (field, part) in fields {
            var match = AttributeContainer()
            match.foundation.dateField = field
            text.replaceAttributes(match, with: mark(part, withoutColor: withoutColor))
        }
        return text
    }

    /// "year month day hours minutes seconds", each word marked like its part: the key to the colors.
    static func legend(withoutColor: Bool) -> AttributedString {
        let words: [(DateSpan.Part, String)] = [
            (.year, String(localized: "year")),
            (.month, String(localized: "month")),
            (.day, String(localized: "day")),
            (.hour, String(localized: "hours")),
            (.minute, String(localized: "minutes")),
            (.second, String(localized: "seconds")),
        ]
        var result = AttributedString()
        for (index, word) in words.enumerated() {
            if index > 0 { result.append(AttributedString(" ")) }
            var piece = AttributedString(word.1)
            piece.mergeAttributes(mark(word.0, withoutColor: withoutColor))
            result.append(piece)
        }
        return result
    }

    /// Resolved per appearance by UIKit, so light and dark mode each get their own shade.
    private nonisolated static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// A filename with its date parts marked. Names without a recognized date stay plain.
struct FilenameText: View {
    let item: Classification
    @Environment(\.marksDatePartsWithoutColor) private var withoutColor

    var body: some View {
        if let name = item.asset.filename {
            Text(DatePartStyle.filename(name, spans: item.filenameDate?.spans ?? [], withoutColor: withoutColor))
                .accessibilityLabel(Text(verbatim: name))
        } else {
            Text("No filename")
                .foregroundStyle(.secondary)
        }
    }
}

/// A date with its parts marked like the filename.
struct MarkedDateText: View {
    let date: Date
    var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
    @Environment(\.marksDatePartsWithoutColor) private var withoutColor

    var body: some View {
        Text(DatePartStyle.date(date, style: style, withoutColor: withoutColor))
            .accessibilityLabel(Text(date.formatted(style)))
    }
}

/// The key to the marks, shown below the filename on the detail screen.
struct DatePartLegend: View {
    @Environment(\.marksDatePartsWithoutColor) private var withoutColor

    var body: some View {
        Text(DatePartStyle.legend(withoutColor: withoutColor))
            .font(.footnote)
            .accessibilityHidden(true)
    }
}
