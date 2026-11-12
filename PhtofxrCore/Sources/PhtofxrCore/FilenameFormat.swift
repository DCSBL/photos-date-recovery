import Foundation

/// One known way cameras and apps put a date in a filename.
///
/// Each format can be switched on or off in Settings. The catalog order is the matching order: specific
/// formats first, the generic ISO format last, so `IMG-20220201-WA0001` is read as WhatsApp (date only)
/// rather than as a generic date.
public struct FilenameFormat: Identifiable, Hashable, Sendable {
    /// Stable identifier, stored in settings and the change journal. Never rename.
    public let id: String
    /// English display name; the app localizes it.
    public let name: String
    public let examples: [String]
    public let clock: FilenameClock
    /// `false` puts every match in the uncertain bucket, however far the dates are apart.
    public let isReliable: Bool
    public let isEnabledByDefault: Bool
    let patterns: [Pattern]

    /// A regular expression plus the meaning of each capture group, in order.
    struct Pattern: Hashable, Sendable {
        let regex: String
        let fields: [Field]

        init(_ regex: String, _ fields: [Field]) {
            self.regex = regex
            self.fields = fields
        }
    }

    enum Field: Hashable, Sendable {
        case year, month, day, hour, minute, second, millisecond
        /// `AM` or `PM` on a 12-hour clock.
        case meridiem
        case epochSeconds, epochMilliseconds
    }

    init(
        id: String,
        name: String,
        examples: [String],
        clock: FilenameClock = .local,
        isReliable: Bool = true,
        isEnabledByDefault: Bool = true,
        patterns: [Pattern]
    ) {
        self.id = id
        self.name = name
        self.examples = examples
        self.clock = clock
        self.isReliable = isReliable
        self.isEnabledByDefault = isEnabledByDefault
        self.patterns = patterns
    }
}

extension FilenameFormat {
    // Building blocks. `[0-9]` instead of `\d`: only ASCII digits are dates here.
    private static let ymd: [Field] = [.year, .month, .day]
    private static let ymdhms: [Field] = [.year, .month, .day, .hour, .minute, .second]
    private static let ymdhmsms: [Field] = ymdhms + [.millisecond]
    private static let y = "([0-9]{4})"
    private static let m2 = "([0-9]{2})"
    /// No digit may follow, so `IMG_20170223_1234567` is not cut short to a valid time.
    private static let end = "(?![0-9])"
    /// No digit may precede a date found in the middle of a name.
    private static let start = "(?<![0-9])"

    /// Every format the app knows, in matching order.
    public static let catalog: [FilenameFormat] = [
        FilenameFormat(
            id: "pixel",
            name: "Google Pixel",
            examples: ["PXL_20210101_123456789.jpg", "PXL_20210101_123456789.MP.jpg"],
            clock: .utc,
            patterns: [
                Pattern("^PXL_\(y)\(m2)\(m2)_\(m2)\(m2)\(m2)([0-9]{3})?\(end)", ymdhmsms),
            ]
        ),
        FilenameFormat(
            id: "android-camera",
            name: "Android camera",
            examples: [
                "IMG_20170223_123456.jpg", "IMG_20170223_123456_HDR.jpg", "IMG_20170223_123456789.jpg",
                "VID_20170223_123456.mp4", "MVIMG_20190101_123456.jpg", "PANO_20170223_123456.jpg",
            ],
            patterns: [
                Pattern(
                    "^(?:IMG|VID|MVIMG|PANO|PORTRAIT|NIGHT|BURST|LMC)_\(y)\(m2)\(m2)_\(m2)\(m2)\(m2)([0-9]{3})?\(end)",
                    ymdhmsms
                ),
                // Pixel bursts before the PXL_ names: 00000IMG_00000_BURST20190101123456_COVER.jpg
                Pattern("^[0-9]{5}IMG_[0-9]{5}_BURST\(y)\(m2)\(m2)\(m2)\(m2)\(m2)", ymdhms),
            ]
        ),
        FilenameFormat(
            id: "onedrive",
            name: "OneDrive camera upload",
            examples: ["20170223_123456000_iOS.jpg"],
            clock: .utc,
            isReliable: false,
            patterns: [
                Pattern("^\(y)\(m2)\(m2)_\(m2)\(m2)\(m2)([0-9]{3})_(?:iOS|Android)", ymdhmsms),
            ]
        ),
        FilenameFormat(
            id: "samsung",
            name: "Samsung Galaxy",
            examples: ["20170223_123456.jpg", "20170223_123456(0).jpg"],
            patterns: [
                Pattern("^\(y)\(m2)\(m2)_\(m2)\(m2)\(m2)\(end)", ymdhms),
            ]
        ),
        FilenameFormat(
            id: "whatsapp",
            name: "WhatsApp",
            examples: ["IMG-20220201-WA0001.jpg", "VID-20220201-WA0001.mp4", "IMG_20220201_WA0001.jpg"],
            patterns: [
                Pattern("^(?:IMG|VID|AUD|PTT|STK|DOC)[-_]\(y)\(m2)\(m2)[-_]WA[0-9]+", ymd),
            ]
        ),
        FilenameFormat(
            id: "whatsapp-export",
            name: "WhatsApp export",
            examples: ["WhatsApp Image 2022-02-01 at 12.34.56.jpeg", "WhatsApp Video 2022-02-01 at 1.02.03 PM.mp4"],
            patterns: [
                Pattern(
                    "^WhatsApp[ -](?:Image|Video|Audio|afbeelding|video|Bild)[ -]\(y)-\(m2)-\(m2)[ _](?:at|om|um|à)[ _]([0-9]{1,2})\\.\(m2)\\.\(m2)(?:[ \\x{00A0}\\x{202F}]?([AP]M)\\b)?",
                    ymdhms + [.meridiem]
                ),
            ]
        ),
        FilenameFormat(
            id: "dropbox",
            name: "Dropbox camera upload",
            examples: ["2015-05-18 20.17.49.jpg", "2015-05-18 20.17.49-1.jpg"],
            patterns: [
                Pattern("^\(y)-\(m2)-\(m2) \(m2)\\.\(m2)\\.\(m2)\(end)", ymdhms),
            ]
        ),
        FilenameFormat(
            id: "android-screenshot",
            name: "Android screenshot",
            examples: ["Screenshot_20170223-123456.png", "Screenshot_2017-02-23-12-34-56.png", "Screenshot_20170223-123456_WhatsApp.jpg"],
            patterns: [
                Pattern("^Screenshot_\(y)\(m2)\(m2)-\(m2)\(m2)\(m2)\(end)", ymdhms),
                Pattern("^Screenshot_\(y)-\(m2)-\(m2)-\(m2)-\(m2)-\(m2)\(end)", ymdhms),
            ]
        ),
        FilenameFormat(
            id: "macos-screenshot",
            name: "Mac screenshot",
            examples: [
                "Screenshot 2023-02-23 at 12.34.56.png", "Schermafbeelding 2023-02-23 om 12.34.56.png",
                "Screen Shot 2017-02-23 at 12.34.56 PM.png",
            ],
            patterns: [
                Pattern(
                    "^(?:Screenshot|Screen Shot|Schermafbeelding|Bildschirmfoto|Capture d.écran) \(y)-\(m2)-\(m2) (?:at|om|um|à) ([0-9]{1,2})\\.\(m2)\\.\(m2)(?:[ \\x{00A0}\\x{202F}]?([AP]M)\\b)?",
                    ymdhms + [.meridiem]
                ),
            ]
        ),
        FilenameFormat(
            id: "signal",
            name: "Signal",
            examples: ["signal-2021-01-25-185030.jpg", "signal-2023-05-12-12-34-56-789.jpg"],
            patterns: [
                Pattern("^signal-\(y)-\(m2)-\(m2)-\(m2)\(m2)\(m2)\(end)", ymdhms),
                Pattern("^signal-\(y)-\(m2)-\(m2)-\(m2)-\(m2)-\(m2)(?:-([0-9]{3}))?\(end)", ymdhmsms),
            ]
        ),
        FilenameFormat(
            id: "telegram",
            name: "Telegram",
            examples: ["photo_2022-02-01_12-34-56.jpg", "video_2022-02-01_12-34-56.mp4"],
            patterns: [
                Pattern("^(?:photo|video)_\(y)-\(m2)-\(m2)_\(m2)-\(m2)-\(m2)\(end)", ymdhms),
            ]
        ),
        FilenameFormat(
            id: "facebook",
            name: "Facebook",
            examples: ["FB_IMG_1486000000000.jpg"],
            clock: .utc,
            patterns: [
                Pattern("^FB_IMG_([0-9]{13})\(end)", [.epochMilliseconds]),
            ]
        ),
        FilenameFormat(
            id: "dji",
            name: "DJI drone",
            examples: ["DJI_20230101123456_0001_D.JPG"],
            patterns: [
                Pattern("^DJI_\(y)\(m2)\(m2)\(m2)\(m2)\(m2)_[0-9]+", ymdhms),
            ]
        ),
        FilenameFormat(
            id: "blackberry",
            name: "BlackBerry",
            examples: ["IMG-20120101-00001.jpg"],
            patterns: [
                Pattern("^IMG-\(y)\(m2)\(m2)-[0-9]{5}\(end)", ymd),
            ]
        ),
        FilenameFormat(
            id: "windows-phone",
            name: "Windows Phone",
            examples: ["WP_20140314_001.jpg", "WP_20140314_12_34_56_Pro.jpg", "wp_ss_20140314_0001.png"],
            patterns: [
                Pattern("^WP_\(y)\(m2)\(m2)_\(m2)_\(m2)_\(m2)\(end)", ymdhms),
                Pattern("^WP_\(y)\(m2)\(m2)_[0-9]{3}\(end)", ymd),
                Pattern("^wp_ss_\(y)\(m2)\(m2)_[0-9]+", ymd),
            ]
        ),
        FilenameFormat(
            id: "skype",
            name: "Skype",
            examples: ["Skype_Picture_2017_02_23T12_34_56_123Z.jpeg"],
            clock: .utc,
            patterns: [
                Pattern("^Skype_Picture_\(y)_\(m2)_\(m2)T\(m2)_\(m2)_\(m2)_([0-9]{3})Z", ymdhmsms),
            ]
        ),
        FilenameFormat(
            id: "iso",
            name: "Date in the name",
            examples: ["Holiday 2017-02-23 12-34-56.jpg", "20170223T123456.jpg", "Scan 20170223_123456.jpg", "2017-02-23.jpg"],
            patterns: [
                Pattern("\(start)\(y)-\(m2)-\(m2)[ _T-]\(m2)[-.:_]\(m2)[-.:_]\(m2)\(end)", ymdhms),
                Pattern("\(start)\(y)\(m2)\(m2)[T_-]\(m2)\(m2)\(m2)\(end)", ymdhms),
                Pattern("\(start)\(y)-\(m2)-\(m2)\(end)", ymd),
            ]
        ),
        FilenameFormat(
            id: "unix-timestamp",
            name: "Bare Unix timestamp",
            examples: ["1486000000.jpg", "1486000000000.jpg"],
            clock: .utc,
            isReliable: false,
            isEnabledByDefault: false,
            patterns: [
                Pattern("^([0-9]{13})\(end)", [.epochMilliseconds]),
                Pattern("^([0-9]{10})\(end)", [.epochSeconds]),
            ]
        ),
        FilenameFormat(
            id: "european-date",
            name: "Day-month-year",
            examples: ["Photo 23-02-2017.jpg"],
            isReliable: false,
            isEnabledByDefault: false,
            patterns: [
                Pattern("\(start)\(m2)-\(m2)-\(y)\(end)", [.day, .month, .year]),
            ]
        ),
    ]
}
