import Foundation
@testable import PhtofxrCore

let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

/// A wall-clock moment in `timeZone`.
func moment(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0,
    in timeZone: TimeZone = amsterdam
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

/// The wall-clock components of `date` in `timeZone`.
func wallClock(_ date: Date, in timeZone: TimeZone = amsterdam) -> DateComponents {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
}

func snapshot(
    _ filename: String?,
    created: Date?,
    added: Date? = nil,
    id: String? = nil,
    kind: MediaKind = .photo
) -> AssetSnapshot {
    AssetSnapshot(id: id ?? filename ?? UUID().uuidString, filename: filename, creationDate: created, addedDate: added, kind: kind)
}
