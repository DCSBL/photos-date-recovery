import Foundation
import Testing
@testable import PhtofxrCore

/// One filename and what the parser must read from it.
struct NameCase: CustomTestStringConvertible, Sendable {
    let name: String
    let format: String
    let date: (Int, Int, Int)
    /// `nil` for date-only names.
    let time: (Int, Int, Int, Int)?
    let clock: FilenameClock

    init(_ name: String, _ format: String, _ date: (Int, Int, Int), _ time: (Int, Int, Int, Int)? = nil, clock: FilenameClock = .local) {
        self.name = name
        self.format = format
        self.date = date
        self.time = time
        self.clock = clock
    }

    var testDescription: String { name }
}

@Suite("Filename date parser")
struct FilenameDateParserTests {
    static let recognized: [NameCase] = [
        // The user's own examples.
        NameCase("IMG_20170223_123456.jpg", "android-camera", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("IMG_20220201_WA0001.jpg", "whatsapp", (2022, 2, 1)),
        NameCase("2015-05-18 20.17.49.jpg", "dropbox", (2015, 5, 18), (20, 17, 49, 0)),
        // Android cameras and video.
        NameCase("IMG_20170223_123456_HDR.jpg", "android-camera", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("IMG_20170223_123456_1.jpg", "android-camera", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("IMG_20170223_123456789.jpg", "android-camera", (2017, 2, 23), (12, 34, 56, 789)),
        NameCase("img_20170223_123456.JPG", "android-camera", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("VID_20170223_123456.mp4", "android-camera", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("MVIMG_20190101_123456.jpg", "android-camera", (2019, 1, 1), (12, 34, 56, 0)),
        NameCase("PANO_20170223_123456.jpg", "android-camera", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("00000IMG_00000_BURST20190101123456_COVER.jpg", "android-camera", (2019, 1, 1), (12, 34, 56, 0)),
        // Pixel names are UTC.
        NameCase("PXL_20210101_123456789.jpg", "pixel", (2021, 1, 1), (12, 34, 56, 789), clock: .utc),
        NameCase("PXL_20210101_123456789.MP.jpg", "pixel", (2021, 1, 1), (12, 34, 56, 789), clock: .utc),
        // Samsung and OneDrive look alike; OneDrive has milliseconds and a platform suffix.
        NameCase("20170223_123456.jpg", "samsung", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("20170223_123456(0).jpg", "samsung", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("20170223_123456_001.jpg", "samsung", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("20170223_123456000_iOS.jpg", "onedrive", (2017, 2, 23), (12, 34, 56, 0), clock: .utc),
        // WhatsApp: date only.
        NameCase("IMG-20220201-WA0001.jpg", "whatsapp", (2022, 2, 1)),
        NameCase("VID-20220201-WA0012.mp4", "whatsapp", (2022, 2, 1)),
        NameCase("IMG-20220201-WA0001 (1).jpg", "whatsapp", (2022, 2, 1)),
        NameCase("WhatsApp Image 2022-02-01 at 12.34.56.jpeg", "whatsapp-export", (2022, 2, 1), (12, 34, 56, 0)),
        NameCase("WhatsApp Image 2022-02-01 at 12.34.56 (1).jpeg", "whatsapp-export", (2022, 2, 1), (12, 34, 56, 0)),
        NameCase("WhatsApp Video 2022-02-01 at 1.02.03 PM.mp4", "whatsapp-export", (2022, 2, 1), (13, 2, 3, 0)),
        NameCase("WhatsApp-afbeelding 2022-02-01 om 09.08.07.jpeg", "whatsapp-export", (2022, 2, 1), (9, 8, 7, 0)),
        // Dropbox.
        NameCase("2015-05-18 20.17.49-1.jpg", "dropbox", (2015, 5, 18), (20, 17, 49, 0)),
        NameCase("2015-05-18 20.17.49 HDR.jpg", "dropbox", (2015, 5, 18), (20, 17, 49, 0)),
        // Screenshots.
        NameCase("Screenshot_20170223-123456.png", "android-screenshot", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("Screenshot_20170223-123456_WhatsApp.jpg", "android-screenshot", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("Screenshot_2017-02-23-12-34-56.png", "android-screenshot", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("Screenshot 2023-02-23 at 12.34.56.png", "macos-screenshot", (2023, 2, 23), (12, 34, 56, 0)),
        NameCase("Schermafbeelding 2023-02-23 om 12.34.56.png", "macos-screenshot", (2023, 2, 23), (12, 34, 56, 0)),
        NameCase("Screen Shot 2017-02-23 at 12.34.56 PM.png", "macos-screenshot", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("Screen Shot 2017-02-23 at 1.34.56 PM.png", "macos-screenshot", (2017, 2, 23), (13, 34, 56, 0)),
        NameCase("Screen Shot 2017-02-23 at 12.34.56 AM.png", "macos-screenshot", (2017, 2, 23), (0, 34, 56, 0)),
        NameCase("Screenshot 2023-02-23 at 1.34.56\u{202F}PM.png", "macos-screenshot", (2023, 2, 23), (13, 34, 56, 0)),
        // Messengers.
        NameCase("signal-2021-01-25-185030.jpg", "signal", (2021, 1, 25), (18, 50, 30, 0)),
        NameCase("signal-2023-05-12-12-34-56-789.jpg", "signal", (2023, 5, 12), (12, 34, 56, 789)),
        NameCase("photo_2022-02-01_12-34-56.jpg", "telegram", (2022, 2, 1), (12, 34, 56, 0)),
        NameCase("video_2022-02-01_12-34-56.mp4", "telegram", (2022, 2, 1), (12, 34, 56, 0)),
        // 1486000000000 ms = 2017-02-02 01:46:40 UTC.
        NameCase("FB_IMG_1486000000000.jpg", "facebook", (2017, 2, 2), (1, 46, 40, 0), clock: .utc),
        NameCase("Skype_Picture_2017_02_23T12_34_56_123Z.jpeg", "skype", (2017, 2, 23), (12, 34, 56, 123), clock: .utc),
        // Other devices.
        NameCase("DJI_20230101123456_0001_D.JPG", "dji", (2023, 1, 1), (12, 34, 56, 0)),
        NameCase("IMG-20120101-00001.jpg", "blackberry", (2012, 1, 1)),
        NameCase("WP_20140314_001.jpg", "windows-phone", (2014, 3, 14)),
        NameCase("WP_20140314_12_34_56_Pro.jpg", "windows-phone", (2014, 3, 14), (12, 34, 56, 0)),
        NameCase("wp_ss_20140314_0001.png", "windows-phone", (2014, 3, 14)),
        // Generic dates anywhere in the name.
        NameCase("Holiday 2017-02-23 12-34-56.jpg", "iso", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("2017-02-23_12-34-56.jpg", "iso", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("20170223T123456.jpg", "iso", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("Scan 20170223_123456.jpg", "iso", (2017, 2, 23), (12, 34, 56, 0)),
        NameCase("2017-02-23.jpg", "iso", (2017, 2, 23)),
        NameCase("Birthday 2017-02-23 (2).jpg", "iso", (2017, 2, 23)),
    ]

    @Test("Recognizes known formats", arguments: FilenameDateParserTests.recognized)
    func recognizes(_ testCase: NameCase) throws {
        let parsed = try #require(FilenameDateParser().parse(testCase.name))
        #expect(parsed.formatID == testCase.format)
        #expect(parsed.year == testCase.date.0)
        #expect(parsed.month == testCase.date.1)
        #expect(parsed.day == testCase.date.2)
        #expect(parsed.clock == testCase.clock)
        if let time = testCase.time {
            let parsedTime = try #require(parsed.time)
            #expect(parsedTime == TimeOfDay(hour: time.0, minute: time.1, second: time.2, millisecond: time.3))
        } else {
            #expect(parsed.time == nil)
        }
        #expect(parsed.isValid)
    }

    static let noDate: [String] = [
        "IMG_1234.JPG", "IMG_E1234.HEIC", "IMG_0001.MOV", "DSC_0001.JPG", "DSCN0001.JPG", "DSCF0001.JPG",
        "P1010001.JPG", "GOPR0001.MP4", "Snapchat-123456789.jpg", "Snapchat-1234567890.jpg",
        "received_1234567890.jpeg", "1486000000.jpg", "1486000000000.jpg",
        "5E1A3F2C-9B7D-4C1E-8F00-1234567890AB.jpeg", "IMG_20170223_1234567.jpg", "Photo 23-02-2017.jpg",
        "", "IMG_.jpg", "photo.jpg", "IMG_201702.jpg",
    ]

    @Test("Leaves names without a date alone", arguments: FilenameDateParserTests.noDate)
    func leavesAlone(_ name: String) {
        #expect(FilenameDateParser().parse(name) == nil)
    }

    @Test("Opt-in formats only match when switched on")
    func optInFormats() throws {
        let all = FilenameDateParser(formats: FilenameFormat.catalog)
        let epoch = try #require(all.parse("1486000000.jpg"))
        #expect(epoch.formatID == "unix-timestamp")
        #expect(epoch.clock == .utc)
        #expect(epoch.year == 2017 && epoch.month == 2 && epoch.day == 2)

        let epochMillis = try #require(all.parse("1486000000000.jpg"))
        #expect(epochMillis.formatID == "unix-timestamp")

        let european = try #require(all.parse("Photo 23-02-2017.jpg"))
        #expect(european.formatID == "european-date")
        #expect(european.year == 2017 && european.month == 2 && european.day == 23)
        #expect(european.time == nil)

        // Snapchat numbers are not anchored at the start, so even an opted-in timestamp skips them.
        #expect(all.parse("Snapchat-1486000000.jpg") == nil)
    }

    @Test("Switching a format off falls through to later formats")
    func disabledFormat() throws {
        let formats = FilenameFormat.catalog.filter { $0.id != "dropbox" && $0.isEnabledByDefault }
        let parsed = try #require(FilenameDateParser(formats: formats).parse("2015-05-18 20.17.49.jpg"))
        #expect(parsed.formatID == "iso")
        #expect(parsed.time == TimeOfDay(hour: 20, minute: 17, second: 49))

        let none = FilenameDateParser(formats: [])
        #expect(none.parse("IMG_20170223_123456.jpg") == nil)
    }

    @Test("Impossible dates are returned but marked invalid", arguments: [
        "IMG_20170230_120000.jpg", "IMG_20170229_120000.jpg", "IMG_20171301_120000.jpg",
        "IMG_20170223_250000.jpg", "IMG_20170223_126100.jpg", "IMG-20170000-WA0001.jpg",
    ])
    func invalidDates(_ name: String) throws {
        let parsed = try #require(FilenameDateParser().parse(name))
        #expect(!parsed.isValid)
        #expect(parsed.resolved(in: .phtofxrUTC, keepingTimeOf: nil) == nil)
    }

    @Test("Leap days")
    func leapDays() throws {
        let parser = FilenameDateParser()
        let leap2016 = try #require(parser.parse("IMG_20160229_120000.jpg"))
        let leap2000 = try #require(parser.parse("IMG_20000229_120000.jpg"))
        let notLeap1900 = try #require(parser.parse("IMG_19000229_120000.jpg"))
        #expect(leap2016.isValid)
        #expect(leap2000.isValid)
        #expect(!notLeap1900.isValid)
    }

    @Test("12-hour clock conversion")
    func meridiem() {
        #expect(FilenameDateParser.to24Hour(12, meridiem: "AM") == 0)
        #expect(FilenameDateParser.to24Hour(12, meridiem: "PM") == 12)
        #expect(FilenameDateParser.to24Hour(1, meridiem: "pm") == 13)
        #expect(FilenameDateParser.to24Hour(11, meridiem: "AM") == 11)
        #expect(FilenameDateParser.to24Hour(15, meridiem: nil) == 15)
    }

    @Test("Every catalog pattern compiles and every example parses with its own format")
    func catalogExamples() throws {
        let parser = FilenameDateParser(formats: FilenameFormat.catalog)
        #expect(Set(FilenameFormat.catalog.map(\.id)).count == FilenameFormat.catalog.count)
        for format in FilenameFormat.catalog {
            #expect(!format.examples.isEmpty, "\(format.id) has no example")
            for example in format.examples {
                let parsed = try #require(parser.parse(example), "\(example) did not parse")
                #expect(parsed.formatID == format.id, "\(example) parsed as \(parsed.formatID), expected \(format.id)")
            }
        }
    }
}

@Suite("Where the date sits in the filename")
struct DateSpanTests {
    func spans(_ name: String, formats: [FilenameFormat] = FilenameFormat.catalog) throws -> [String] {
        let parsed = try #require(FilenameDateParser(formats: formats).parse(name))
        let utf16 = Array(name.utf16)
        return parsed.spans.map { span in
            "\(span.part.rawValue)=" + String(decoding: utf16[span.utf16Range], as: UTF16.self)
        }
    }

    @Test("Android camera name: every part in order")
    func android() throws {
        #expect(try spans("IMG_20170223_123456.jpg") == ["year=2017", "month=02", "day=23", "hour=12", "minute=34", "second=56"])
    }

    @Test("Milliseconds are their own part")
    func milliseconds() throws {
        #expect(try spans("PXL_20210101_123456789.jpg").last == "fraction=789")
    }

    @Test("Date-only names have no time parts")
    func dateOnly() throws {
        #expect(try spans("IMG-20220201-WA0001.jpg") == ["year=2022", "month=02", "day=01"])
    }

    @Test("Day-month-year names are still listed in filename order")
    func europeanOrder() throws {
        #expect(try spans("Photo 23-02-2017.jpg") == ["day=23", "month=02", "year=2017"])
    }

    @Test("Spans count UTF-16 like NSRange, also after non-ASCII text")
    func utf16() throws {
        #expect(try spans("Vakantie é 2017-02-23 12-34-56.jpg") == ["year=2017", "month=02", "day=23", "hour=12", "minute=34", "second=56"])
    }

    @Test("Epoch names have no spans")
    func epoch() throws {
        #expect(try spans("FB_IMG_1486000000000.jpg").isEmpty)
    }

    @Test("AM/PM counts as part of the hour")
    func meridiem() throws {
        #expect(try spans("Screen Shot 2017-02-23 at 1.34.56 PM.png").contains("hour=PM"))
    }
}

@Suite("Cutting a filename into date parts")
struct DateSegmentTests {
    func cut(_ name: String) throws -> [String] {
        let parsed = try #require(FilenameDateParser().parse(name))
        return DateSpan.segments(of: name, spans: parsed.spans).map { segment in
            segment.part.map { "[\($0.rawValue):\(segment.text)]" } ?? segment.text
        }
    }

    @Test("Plain text and parts alternate and add up to the whole name")
    func whole() throws {
        let name = "IMG_20130109_101536.jpg"
        let segments = try cut(name)
        #expect(segments == ["IMG_", "[year:2013]", "[month:01]", "[day:09]", "_", "[hour:10]", "[minute:15]", "[second:36]", ".jpg"])
        let parsed = try #require(FilenameDateParser().parse(name))
        #expect(DateSpan.segments(of: name, spans: parsed.spans).map(\.text).joined() == name)
    }

    @Test("Non-ASCII text before the date stays intact")
    func nonASCII() throws {
        let name = "Café 🎉 2017-02-23 12-34-56.jpg"
        let parsed = try #require(FilenameDateParser().parse(name))
        let segments = DateSpan.segments(of: name, spans: parsed.spans)
        #expect(segments.map(\.text).joined() == name)
        #expect(segments.first?.text == "Café 🎉 ")
        #expect(segments.first { $0.part == .year }?.text == "2017")
    }

    @Test("Without spans the name is one plain segment; broken spans are ignored")
    func noSpans() {
        #expect(DateSpan.segments(of: "IMG_1234.JPG", spans: []) == [DateSpan.Segment("IMG_1234.JPG")])
        let broken = [DateSpan(part: .year, utf16Range: 2..<6), DateSpan(part: .month, utf16Range: 4..<8), DateSpan(part: .day, utf16Range: 10..<40)]
        #expect(DateSpan.segments(of: "a_2013_x", spans: broken).map(\.text) == ["a_", "2013", "_x"])
        #expect(DateSpan.segments(of: "", spans: []).isEmpty)
    }
}
