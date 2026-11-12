#if DEBUG
import Foundation
import PhtofxrCore
import UIKit

/// A fixed library for UI tests and previews (launch argument `-phtofxrUITest`): the user's case of an old
/// import on 11 and 12 October 2016, plus one example of every other category.
final class FakePhotoLibrary: PhotoLibraryClient {
    private var access: LibraryAccess
    private(set) var assets: [AssetSnapshot]
    private(set) var captions: [String: String] = [:]

    init(access: LibraryAccess = .notDetermined, assets: [AssetSnapshot] = FakePhotoLibrary.fixture()) {
        self.access = access
        self.assets = assets
    }

    func currentAccess() -> LibraryAccess { access }

    func requestAccess() async -> LibraryAccess {
        if access == .notDetermined { access = .full }
        return access
    }

    func snapshots(kinds: Set<MediaKind>, progress: @escaping @Sendable (Double) -> Void) async -> [AssetSnapshot] {
        progress(1)
        return assets.filter { kinds.contains($0.kind) }
    }

    func thumbnail(for id: String, pixelSide: CGFloat) async -> UIImage? { nil }

    func diagnostics(sampleSize: Int) async -> DiagnosticsReport {
        var report = DiagnosticsReport()
        report.total = assets.count
        report.missingAssetFilename = assets.filter { $0.filename == nil }.count
        report.missingResourceFilename = report.missingAssetFilename
        report.missingAddedDate = assets.filter { $0.addedDate == nil }.count
        report.samples = assets.prefix(sampleSize).map { asset in
            AssetDiagnostics(
                id: asset.id,
                assetFilename: asset.filename,
                resourceFilenames: asset.filename.map { ["photo: \($0)"] } ?? [],
                creationDate: asset.creationDate,
                addedDate: asset.addedDate,
                modificationDate: asset.addedDate,
                caption: nil
            )
        }
        return report
    }

    func apply(_ edits: [DateEdit]) async throws -> Set<String> {
        var changed: Set<String> = []
        for edit in edits {
            guard let index = assets.firstIndex(where: { $0.id == edit.assetID }) else { continue }
            let old = assets[index]
            assets[index] = AssetSnapshot(id: old.id, filename: old.filename, creationDate: edit.newCreationDate, addedDate: old.addedDate, kind: old.kind)
            var caption: String? = captions[edit.assetID]
            if let line = edit.captionLineToRemove { caption = CaptionEditor.removing(line, from: caption) }
            if let line = edit.captionLineToAdd { caption = CaptionEditor.adding(line, to: caption) }
            captions[edit.assetID] = caption
            changed.insert(edit.assetID)
        }
        return changed
    }

    func presentLimitedLibraryPicker() {}

    static func fixture(timeZone: TimeZone = .current) -> [AssetSnapshot] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0, _ s: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
        }

        var assets: [AssetSnapshot] = []
        // The import: every photo got the moment it was imported as its date.
        for day in [11, 12] {
            for i in 0..<60 {
                let imported = at(2016, 10, day, 14, 0, 0).addingTimeInterval(TimeInterval(i * 9))
                let name: String
                switch i % 4 {
                case 0: name = String(format: "IMG_2013%02d%02d_1015%02d.jpg", 1 + i % 12, 1 + i % 28, i % 60)
                case 1: name = String(format: "IMG-2015%02d%02d-WA%04d.jpg", 1 + i % 12, 1 + i % 28, i)
                case 2: name = String(format: "2014-%02d-%02d 20.17.%02d.jpg", 1 + i % 12, 1 + i % 28, i % 60)
                default: name = String(format: "IMG_%04d.JPG", i)
                }
                assets.append(AssetSnapshot(id: "import-\(day)-\(i)", filename: name, creationDate: imported, addedDate: imported, kind: .photo))
            }
        }
        // Photos with their own dates.
        assets += [
            AssetSnapshot(id: "conflict", filename: "IMG_20170101_101010.jpg", creationDate: at(2018, 6, 1), addedDate: at(2019, 1, 1), kind: .photo),
            AssetSnapshot(id: "week-off", filename: "IMG_20190305_120000.jpg", creationDate: at(2019, 3, 8), addedDate: at(2019, 3, 8), kind: .photo),
            AssetSnapshot(id: "correct", filename: "IMG_20190701_201500.jpg", creationDate: at(2019, 7, 1, 20, 15), addedDate: at(2019, 7, 2), kind: .photo),
            AssetSnapshot(id: "reset", filename: "IMG_20120505_101010.jpg", creationDate: at(1990, 1, 1, 0, 0), addedDate: at(2016, 10, 11), kind: .photo),
            AssetSnapshot(id: "reset-no-name", filename: "DSC_0001.JPG", creationDate: at(2000, 1, 1, 0, 12), addedDate: at(2016, 10, 11), kind: .photo),
            AssetSnapshot(id: "invalid", filename: "IMG_20170230_120000.jpg", creationDate: at(2020, 2, 2), addedDate: at(2020, 2, 2), kind: .photo),
            AssetSnapshot(id: "video", filename: "VID_20150808_181818.mp4", creationDate: at(2016, 10, 11, 15), addedDate: at(2016, 10, 11, 15), kind: .video),
            AssetSnapshot(id: "screenshot", filename: "Screenshot_20160301-101010.png", creationDate: at(2016, 10, 12, 15), addedDate: at(2016, 10, 12, 15), kind: .screenshot),
        ]
        return assets
    }
}
#endif
