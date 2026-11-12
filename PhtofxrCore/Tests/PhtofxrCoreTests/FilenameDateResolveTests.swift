import Foundation
import Testing
@testable import PhtofxrCore

@Suite("Placing a filename date in time")
struct FilenameDateResolveTests {
    @Test("Local names are read as wall-clock time in the chosen time zone")
    func localWallClock() throws {
        let name = try #require(FilenameDateParser().parse("IMG_20170223_123456.jpg"))
        let date = try #require(name.resolved(in: amsterdam, keepingTimeOf: nil))
        #expect(date == moment(2017, 2, 23, 12, 34, 56))
        // Winter time: one hour ahead of UTC.
        #expect(wallClock(date, in: .phtofxrUTC).hour == 11)
    }

    @Test("Summer time is applied per date, not per scan")
    func summerTime() throws {
        let name = try #require(FilenameDateParser().parse("IMG_20170723_123456.jpg"))
        let date = try #require(name.resolved(in: amsterdam, keepingTimeOf: nil))
        #expect(wallClock(date, in: .phtofxrUTC).hour == 10)
    }

    @Test("UTC names are converted to local time")
    func utcName() throws {
        // 23:30 UTC on New Year's Eve is already 00:30 on 1 January in Amsterdam.
        let name = try #require(FilenameDateParser().parse("PXL_20201231_233000000.jpg"))
        let date = try #require(name.resolved(in: amsterdam, keepingTimeOf: nil))
        let local = wallClock(date)
        #expect(local.year == 2021 && local.month == 1 && local.day == 1)
        #expect(local.hour == 0 && local.minute == 30)
    }

    @Test("A date-only name keeps the current time of day")
    func dateOnlyKeepsTime() throws {
        let name = try #require(FilenameDateParser().parse("IMG-20220201-WA0001.jpg"))
        let current = moment(2016, 10, 11, 14, 23, 17)
        let date = try #require(name.resolved(in: amsterdam, keepingTimeOf: current))
        #expect(date == moment(2022, 2, 1, 14, 23, 17))
    }

    @Test("A date-only name without anything to keep gets noon")
    func dateOnlyNoon() throws {
        let name = try #require(FilenameDateParser().parse("IMG-20220201-WA0001.jpg"))
        let date = try #require(name.resolved(in: amsterdam, keepingTimeOf: nil))
        #expect(date == moment(2022, 2, 1, 12, 0, 0))
    }

    @Test("A time in the spring-forward gap still resolves to that morning")
    func springForwardGap() throws {
        // 26 March 2017: clocks in Amsterdam jump from 02:00 to 03:00, so 02:30 does not exist.
        let name = try #require(FilenameDateParser().parse("IMG_20170326_023000.jpg"))
        let date = try #require(name.resolved(in: amsterdam, keepingTimeOf: nil))
        let local = wallClock(date)
        #expect(local.day == 26)
        #expect(local.hour == 1 || local.hour == 3)
    }

    @Test("A time in the fall-back hour resolves to one of its two moments")
    func fallBackHour() throws {
        // 29 October 2017: 02:30 happens twice in Amsterdam.
        let name = try #require(FilenameDateParser().parse("IMG_20171029_023000.jpg"))
        let date = try #require(name.resolved(in: amsterdam, keepingTimeOf: nil))
        let utcHour = wallClock(date, in: .phtofxrUTC).hour
        #expect(utcHour == 0 || utcHour == 1)
        #expect(wallClock(date).hour == 2)
    }

    @Test("Milliseconds survive")
    func milliseconds() throws {
        let name = try #require(FilenameDateParser().parse("IMG_20170223_123456789.jpg"))
        let date = try #require(name.resolved(in: amsterdam, keepingTimeOf: nil))
        let fraction = date.timeIntervalSince(moment(2017, 2, 23, 12, 34, 56))
        #expect(abs(fraction - 0.789) < 0.001)
    }
}
