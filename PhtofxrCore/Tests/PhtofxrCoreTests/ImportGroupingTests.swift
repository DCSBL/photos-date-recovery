import Foundation
import Testing
@testable import PhtofxrCore

@Suite("Grouping by import day")
struct ImportGroupingTests {
    func item(_ id: String, added: Date?, proposed: Date? = nil, category: DateCategory = .certain) -> Classification {
        Classification(
            asset: snapshot("\(id).jpg", created: moment(2016, 10, 11), added: added, id: id),
            category: category,
            filenameDate: nil,
            proposedDate: proposed,
            reasons: []
        )
    }

    @Test("Largest imports come first, photos without an added date last")
    func largestFirst() {
        let items = [
            item("a1", added: moment(2016, 10, 11, 9)),
            item("b1", added: moment(2016, 10, 12, 9)),
            item("b2", added: moment(2016, 10, 12, 23)),
            item("x", added: nil),
            item("c1", added: moment(2020, 1, 1)),
        ]
        let groups = ImportGrouping.groups(items, timeZone: amsterdam)
        #expect(groups.map(\.day) == [
            DayKey(year: 2016, month: 10, day: 12),
            DayKey(year: 2020, month: 1, day: 1),
            DayKey(year: 2016, month: 10, day: 11),
            nil,
        ])
        #expect(groups.first?.items.count == 2)
        #expect(groups.last?.id == "unknown")
    }

    @Test("Date orders")
    func dateOrders() {
        let items = [
            item("old", added: moment(2016, 10, 11)),
            item("new", added: moment(2020, 1, 1)),
            item("none", added: nil),
        ]
        #expect(ImportGrouping.groups(items, timeZone: amsterdam, order: .newestFirst).map(\.items.first?.id) == ["new", "old", "none"])
        #expect(ImportGrouping.groups(items, timeZone: amsterdam, order: .oldestFirst).map(\.items.first?.id) == ["old", "new", "none"])
    }

    @Test("Days follow the chosen time zone")
    func timeZoneDays() {
        // 00:30 on 12 October in Amsterdam (summer time) is 22:30 on the 11th in UTC.
        let late = item("late", added: moment(2016, 10, 12, 0, 30))
        #expect(ImportGrouping.groups([late], timeZone: amsterdam).first?.day == DayKey(year: 2016, month: 10, day: 12))
        #expect(ImportGrouping.groups([late], timeZone: .phtofxrUTC).first?.day == DayKey(year: 2016, month: 10, day: 11))
    }

    @Test("Within an import, items follow the proposed date and split into certain and uncertain")
    func itemsInsideGroup() throws {
        let added = moment(2016, 10, 11)
        let items = [
            item("late", added: added, proposed: moment(2015, 1, 1)),
            item("early", added: added, proposed: moment(2013, 1, 1)),
            item("unsure", added: added, proposed: moment(2014, 1, 1), category: .uncertain),
        ]
        let group = try #require(ImportGrouping.groups(items, timeZone: amsterdam).first)
        #expect(group.items.map(\.id) == ["early", "unsure", "late"])
        #expect(group.certain.map(\.id) == ["early", "late"])
        #expect(group.uncertain.map(\.id) == ["unsure"])
    }

    @Test("Day keys order like the calendar")
    func dayKeyOrder() {
        #expect(DayKey(year: 2016, month: 10, day: 11) < DayKey(year: 2016, month: 10, day: 12))
        #expect(DayKey(year: 2016, month: 9, day: 30) < DayKey(year: 2016, month: 10, day: 1))
        #expect(DayKey(year: 2015, month: 12, day: 31) < DayKey(year: 2016, month: 1, day: 1))
        #expect(DayKey(year: 2016, month: 10, day: 11).date(in: amsterdam) == moment(2016, 10, 11))
    }
}
