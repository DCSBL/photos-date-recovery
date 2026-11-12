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
