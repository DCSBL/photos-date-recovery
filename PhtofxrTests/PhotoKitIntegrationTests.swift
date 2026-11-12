import Foundation
import Photos
import PhtofxrCore
import Testing
@testable import Phtofxr

/// Real PhotoKit in the simulator. CI puts photos with known filenames in the simulator's library
/// (scripts/ci/seed-simulator-photos.sh), grants access, and sets PHTOFXR_SEEDED=1; elsewhere this is skipped.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PHTOFXR_SEEDED"] == "1"))
struct PhotoKitIntegrationTests {
    static let seededNames = [
        "IMG_20170223_123456.jpg",
        "IMG-20220201-WA0001.jpg",
        "2015-05-18 20.17.49.jpg",
        "PXL_20210101_123456789.jpg",
        "IMG_1234.jpg",
    ]

    @Test("Reads the original filenames and added dates of seeded photos")
    func readsSeededPhotos() async throws {
        let library = LivePhotoLibrary()
        let access = library.currentAccess()
        try #require(access == .full, "Photo access is \(access); run `simctl privacy grant photos` first")

        let snapshots = await library.snapshots(kinds: [.photo, .video, .screenshot]) { _ in }
        for snapshot in snapshots {
            // Shows in the CI log: what PhotoKit really reports for each name.
            print("PHTOFXR snapshot", snapshot.filename ?? "nil", String(describing: snapshot.creationDate), String(describing: snapshot.addedDate), snapshot.kind)
        }
        let names = Set(snapshots.compactMap(\.filename))
        for name in Self.seededNames {
            #expect(names.contains(name), "\(name) not found; PhotoKit reported \(names.sorted())")
        }
        let seeded = snapshots.filter { Self.seededNames.contains($0.filename ?? "") }
        #expect(seeded.allSatisfy { $0.addedDate != nil })

        let classified = Classifier().classify(seeded)
        let whatsapp = classified.first { $0.asset.filename == "IMG-20220201-WA0001.jpg" }
        #expect(whatsapp?.filenameDate?.formatID == "whatsapp")
        let plain = classified.first { $0.asset.filename == "IMG_1234.jpg" }
        #expect(plain?.category == .noDateInName)
    }

    /// A1–A4 in the simulator: a date and caption change through a real change block, the added date untouched,
    /// and the revert. If iOS shows a permission alert for the change, nothing taps it and the time limit ends the test.
    @Test("Changes a date and caption through PhotoKit and reverts both", .timeLimit(.minutes(2)))
    func applyAndRevert() async throws {
        let library = LivePhotoLibrary()
        try #require(library.currentAccess() == .full)
        let snapshots = await library.snapshots(kinds: [.photo]) { _ in }
        let target = try #require(snapshots.first { $0.filename == "IMG_20170223_123456.jpg" })
        let original = try #require(target.creationDate)
        let newDate = try #require(FilenameDateParser().parse("IMG_20170223_123456.jpg")?.resolved(in: .current, keepingTimeOf: nil))
        let line = "Phtofxr: integration test"

        let changed = try await library.apply([DateEdit(assetID: target.id, newCreationDate: newDate, captionLineToAdd: line)])
        #expect(changed == [target.id])
        let afterApply = try #require(PHAsset.fetchAssets(withLocalIdentifiers: [target.id], options: nil).firstObject)
        print("PHTOFXR applied", String(describing: afterApply.creationDate), String(describing: afterApply.addedDate), afterApply.extendedMetadata.caption ?? "nil")
        #expect(abs((afterApply.creationDate ?? .distantPast).timeIntervalSince(newDate)) < 1)
        #expect(afterApply.addedDate == target.addedDate)
        #expect(afterApply.extendedMetadata.caption?.contains(line) == true)

        let reverted = try await library.apply([DateEdit(assetID: target.id, newCreationDate: original, captionLineToRemove: line)])
        #expect(reverted == [target.id])
        let afterRevert = try #require(PHAsset.fetchAssets(withLocalIdentifiers: [target.id], options: nil).firstObject)
        print("PHTOFXR reverted", String(describing: afterRevert.creationDate), afterRevert.extendedMetadata.caption ?? "nil")
        #expect(abs((afterRevert.creationDate ?? .distantPast).timeIntervalSince(original)) < 1)
        #expect(afterRevert.extendedMetadata.caption?.contains(line) != true)
        #expect(afterRevert.addedDate == target.addedDate)
    }

    @Test("Diagnostics read the whole library")
    func diagnostics() async {
        let report = await LivePhotoLibrary().diagnostics(sampleSize: 10)
        print("PHTOFXR diagnostics", report.total, report.missingAssetFilename, report.missingResourceFilename, report.differentFilenames, report.missingAddedDate, report.duration)
        for sample in report.samples {
            print("PHTOFXR sample", sample.assetFilename ?? "nil", sample.resourceFilenames, String(describing: sample.addedDate))
        }
        #expect(report.total >= Self.seededNames.count)
        #expect(report.missingAddedDate == 0)
    }
}
