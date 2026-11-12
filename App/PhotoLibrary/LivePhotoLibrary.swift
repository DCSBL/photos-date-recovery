import Foundation
import Photos
import PhtofxrCore
import UIKit

/// PhotoKit, read-only. Every image request has network access switched off: the app never talks to iCloud.
final class LivePhotoLibrary: PhotoLibraryClient {
    private let imageManager = PHCachingImageManager()

    func currentAccess() -> LibraryAccess {
        Self.access(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAccess() async -> LibraryAccess {
        Self.access(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    func snapshots(kinds: Set<MediaKind>, progress: @escaping @Sendable (Double) -> Void) async -> [AssetSnapshot] {
        await Task.detached(priority: .userInitiated) {
            Self.readSnapshots(kinds: kinds, progress: progress)
        }.value
    }

    func thumbnail(for id: String, pixelSide: CGFloat) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let size = CGSize(width: pixelSide, height: pixelSide)
        if let image = await requestImage(asset, size: size, mode: .highQualityFormat) { return image }
        // The full-quality image may only be in iCloud; the small local one is better than nothing.
        return await requestImage(asset, size: size, mode: .fastFormat)
    }

    func diagnostics(sampleSize: Int) async -> DiagnosticsReport {
        await Task.detached(priority: .userInitiated) {
            Self.readDiagnostics(sampleSize: sampleSize)
        }.value
    }

    func presentLimitedLibraryPicker() {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard var top = window?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }

    // MARK: - PhotoKit reading (off the main actor)

    private func requestImage(_ asset: PHAsset, size: CGSize, mode: PHImageRequestOptionsDeliveryMode) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        // Both modes call the handler exactly once, so the continuation resumes once.
        options.deliveryMode = mode
        options.resizeMode = .fast
        return await withCheckedContinuation { continuation in
            _ = imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    nonisolated static func access(_ status: PHAuthorizationStatus) -> LibraryAccess {
        switch status {
        case .authorized: .full
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    nonisolated static func fetchOptions(kinds: Set<MediaKind>) -> PHFetchOptions? {
        let wantsImages = kinds.contains(.photo) || kinds.contains(.screenshot)
        let wantsVideos = kinds.contains(.video)
        guard wantsImages || wantsVideos else { return nil }
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        // iOS 27: fetch the asset-level filename together with the asset instead of one query per photo.
        options.prefetchAssetExtendedMetadata = true
        if wantsImages && !wantsVideos {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        } else if wantsVideos && !wantsImages {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        } else {
            options.predicate = NSPredicate(
                format: "mediaType == %d || mediaType == %d",
                PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
            )
        }
        return options
    }

    nonisolated static func readSnapshots(kinds: Set<MediaKind>, progress: (Double) -> Void) -> [AssetSnapshot] {
        guard let options = fetchOptions(kinds: kinds) else { return [] }
        let result = PHAsset.fetchAssets(with: options)
        let total = result.count
        var snapshots: [AssetSnapshot] = []
        snapshots.reserveCapacity(total)
        for index in 0..<total {
            let item = snapshot(of: result.object(at: index))
            if kinds.contains(item.kind) { snapshots.append(item) }
            if index % 500 == 0 { progress(Double(index) / Double(total)) }
        }
        progress(1)
        return snapshots
    }

    nonisolated static func snapshot(of asset: PHAsset) -> AssetSnapshot {
        AssetSnapshot(
            id: asset.localIdentifier,
            filename: filename(of: asset),
            creationDate: asset.creationDate,
            addedDate: asset.addedDate,
            kind: kind(of: asset)
        )
    }

    /// The asset-level name first; Apple says resource names can differ from it, so the main resource is the fallback.
    nonisolated static func filename(of asset: PHAsset) -> String? {
        if let name = asset.extendedMetadata.originalFilename, !name.isEmpty { return name }
        return primaryResource(of: PHAssetResource.assetResources(for: asset))?.filename
    }

    nonisolated static func primaryResource(of resources: [PHAssetResource]) -> PHAssetResource? {
        resources.first { $0.type == .photo || $0.type == .video } ?? resources.first
    }

    nonisolated static func kind(of asset: PHAsset) -> MediaKind {
        switch asset.mediaType {
        case .video: .video
        case .image: asset.mediaSubtypes.contains(.photoScreenshot) ? .screenshot : .photo
        default: .other
        }
    }

    nonisolated static func readDiagnostics(sampleSize: Int) -> DiagnosticsReport {
        let clock = ContinuousClock()
        let start = clock.now
        let options = PHFetchOptions()
        options.prefetchAssetExtendedMetadata = true
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)

        var report = DiagnosticsReport()
        report.total = result.count
        // An even spread over the library, so an old import shows up next to recent photos.
        let step = max(1, result.count / max(sampleSize, 1))
        for index in 0..<result.count {
            let asset = result.object(at: index)
            let assetName = asset.extendedMetadata.originalFilename
            let resources = PHAssetResource.assetResources(for: asset)
            let resourceName = primaryResource(of: resources)?.filename
            if assetName == nil { report.missingAssetFilename += 1 }
            if resourceName == nil { report.missingResourceFilename += 1 }
            if let assetName, let resourceName, assetName != resourceName { report.differentFilenames += 1 }
            if asset.addedDate == nil { report.missingAddedDate += 1 }
            if index % step == 0, report.samples.count < sampleSize {
                report.samples.append(AssetDiagnostics(
                    id: asset.localIdentifier,
                    assetFilename: assetName,
                    resourceFilenames: resources.map { "\(label($0.type)): \($0.filename ?? "–")" },
                    creationDate: asset.creationDate,
                    addedDate: asset.addedDate,
                    modificationDate: asset.modificationDate,
                    caption: asset.extendedMetadata.caption
                ))
            }
        }
        report.duration = start.duration(to: clock.now)
        return report
    }

    nonisolated static func label(_ type: PHAssetResourceType) -> String {
        switch type {
        case .photo: "photo"
        case .video: "video"
        case .audio: "audio"
        case .alternatePhoto: "alternate photo"
        case .fullSizePhoto: "edited photo"
        case .fullSizeVideo: "edited video"
        case .adjustmentData: "adjustments"
        case .pairedVideo: "Live Photo video"
        default: "type \(type.rawValue)"
        }
    }
}
