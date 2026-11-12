import Foundation
import PhtofxrCore

// User-facing names for Core values. String(localized:) keeps them in the string catalog.

extension ResultSection {
    var title: String {
        switch self {
        case .review: String(localized: "To review")
        case .suspicious: String(localized: "Suspicious")
        case .alreadyCorrect: String(localized: "Already correct")
        case .noDateInName: String(localized: "No date in name")
        case .skipped: String(localized: "Skipped")
        case .changedByApp: String(localized: "Changed by Phtofxr")
        }
    }

    var systemImage: String {
        switch self {
        case .review: "calendar.badge.clock"
        case .suspicious: "exclamationmark.triangle"
        case .alreadyCorrect: "checkmark.circle"
        case .noDateInName: "questionmark.circle"
        case .skipped: "arrow.uturn.backward.circle"
        case .changedByApp: "clock.arrow.circlepath"
        }
    }
}

extension DateCategory {
    var title: String {
        switch self {
        case .certain: String(localized: "Certain")
        case .uncertain: String(localized: "Uncertain")
        case .suspicious: String(localized: "Suspicious")
        case .alreadyCorrect: String(localized: "Already correct")
        case .noDateInName: String(localized: "No date in name")
        case .skipped: String(localized: "Skipped")
        case .changedByApp: String(localized: "Changed by Phtofxr")
        }
    }
}

extension Reason {
    var explanation: String {
        switch self {
        case .noDateInName: String(localized: "The filename has no recognizable date.")
        case .invalidDateInName: String(localized: "The date in the filename does not exist.")
        case .nameBeforeMinimumYear: String(localized: "The date in the filename is earlier than the minimum year.")
        case .nameInFuture: String(localized: "The date in the filename is in the future.")
        case .missingCreationDate: String(localized: "The photo has no date in Photos.")
        case .matchesName: String(localized: "The date in Photos matches the filename.")
        case .smallDifference: String(localized: "The dates are between a day and a week apart.")
        case .unreliableFormat: String(localized: "This filename format is not always reliable.")
        case .nearAddedDate: String(localized: "The date in Photos is the moment it was added: it was probably filled in at import.")
        case .pileDay(let count): String(localized: "The date in Photos falls on a day with \(count) photos whose names point elsewhere.")
        case .cameraResetDate: String(localized: "The date in Photos looks like a camera whose clock was reset.")
        case .conflictsWithOwnDate: String(localized: "The photo has its own date, and the filename disagrees.")
        case .skippedByUser: String(localized: "You chose not to keep this proposal.")
        case .changedByApp: String(localized: "Phtofxr already changed this date.")
        }
    }
}

extension FilenameFormat {
    /// Brand names stay as they are; the generic formats get a translated name.
    var displayName: String {
        switch id {
        case "android-camera": String(localized: "Android camera")
        case "onedrive": String(localized: "OneDrive camera upload")
        case "whatsapp-export": String(localized: "WhatsApp export")
        case "dropbox": String(localized: "Dropbox camera upload")
        case "android-screenshot": String(localized: "Android screenshot")
        case "macos-screenshot": String(localized: "Mac screenshot")
        case "dji": String(localized: "DJI drone")
        case "iso": String(localized: "Date in the name")
        case "unix-timestamp": String(localized: "Bare Unix timestamp")
        case "european-date": String(localized: "Day-month-year")
        default: name
        }
    }
}

extension MediaKind {
    var title: String {
        switch self {
        case .photo: String(localized: "Photos")
        case .video: String(localized: "Videos")
        case .screenshot: String(localized: "Screenshots")
        case .other: String(localized: "Other")
        }
    }
}

/// "3 years, 2 months" style difference between two dates.
func differenceText(_ seconds: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .full
    formatter.maximumUnitCount = 2
    formatter.allowedUnits = [.year, .month, .day, .hour, .minute]
    let text = formatter.string(from: abs(seconds)) ?? ""
    return seconds < 0 ? String(localized: "\(text) earlier") : String(localized: "\(text) later")
}
