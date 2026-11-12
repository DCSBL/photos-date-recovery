import Foundation
import PhtofxrCore
import UIKit

/// What the app needs from the photo library. PhotoKit in the app; a fixed set of photos in UI tests.
protocol PhotoLibraryClient: AnyObject {
    func currentAccess() -> LibraryAccess
    /// Shows the system permission prompt when the user has not decided yet.
    func requestAccess() async -> LibraryAccess
    /// Reads names and dates of every item of the given kinds. Never downloads anything.
    func snapshots(kinds: Set<MediaKind>, progress: @escaping @Sendable (Double) -> Void) async -> [AssetSnapshot]
    /// A thumbnail from what is stored on this device; `nil` when only iCloud has it.
    func thumbnail(for id: String, pixelSide: CGFloat) async -> UIImage?
    func diagnostics(sampleSize: Int) async -> DiagnosticsReport
    /// Lets the user change which photos a limited-access app may see.
    func presentLimitedLibraryPicker()
}
