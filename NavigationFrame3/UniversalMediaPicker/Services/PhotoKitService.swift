import Foundation
import Photos
import PhotosUI
import UIKit
import Observation

/// Process-wide thumbnail cache. Keys include `modificationDate` so an
/// in-place edit in `Photos.app` (crop, markup, filter — same identifier,
/// new pixels) produces a cache miss and a fresh fetch. Without this, the
/// grid would happily serve pre-edit pixels until the entry was evicted.
///
/// One entry per asset, regardless of requested size. `loadThumbnail`
/// always stores the LARGEST image ever fetched for that asset and
/// downscales for smaller consumers via SwiftUI's `.scaledToFill()`. The
/// alternative — keying by size too — meant a small grid-cell request
/// arriving after a larger previewer request would overwrite the high-res
/// image with a low-res one, causing visible blur the next time the
/// previewer reopened. See `loadThumbnail` for the comparison logic.
public enum ThumbnailCache {
    public static let shared: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 500
        return c
    }()

    /// Single source of truth for cache keys — call this from every read
    /// AND every write so they cannot drift apart.
    public static func key(for asset: PHAsset) -> NSString {
        let mod = asset.modificationDate?.timeIntervalSinceReferenceDate ?? 0
        return "\(asset.localIdentifier)|\(mod)" as NSString
    }
}

/// `@Observable` facade exposing the picker's published PhotoKit state.
///
/// Holds `recentAssets`, `authStatus`, and `albums` for SwiftUI views/VMs to
/// observe via computed-property proxies. Uses `PhotoLibraryService` (the
/// mini-repository) for the heavy off-main data work.
///
/// Architecture notes:
/// - NO class-level `@MainActor`. Async data methods are nonisolated so
///   awaiting them hops to the cooperative thread pool per SE-0338, and the
///   heavy PhotoKit calls inside `PhotoLibraryService` run off the main thread.
///   Observable-state writers and UIKit-touching methods are individually
///   `@MainActor`-annotated; `await MainActor.run` is used inside async methods
///   to hop back to main for observable writes.
/// - `PHPhotoLibraryChangeObserver` conformance lives in a dedicated extension.
@Observable
public final class PhotoKitService: NSObject {
    @MainActor public static let shared = PhotoKitService()

    public var recentAssets: [PHAsset] = []
    public var authStatus: PHAuthorizationStatus = .notDetermined
    public var albums: [PhotoLibraryService.AlbumInfo] = []

    private let library = PhotoLibraryService.shared

    @MainActor
    private override init() {
        super.init()
        self.authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - Auth

    /// Silently re-reads the current auth status without prompting. Cheap;
    /// safe to call repeatedly from scenePhase observers.
    @MainActor
    public func updateAuthStatus() {
        let newStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        setAuthStatus(newStatus)
    }

    // MARK: - Prewarm (called by MediaPickerModifier infrastructure)

    /// Warms recents + the album list when authorization is already
    /// granted. Does NOT prompt — first-time users hit the auth prompt at
    /// their intent moment (when they actually open the picker).
    ///
    /// Both warms run sequentially: recents first (fast, drives the
    /// viewfinder + gallery shortcut), then the album list (powers the
    /// dropdown). Running them sequentially keeps PhotoKit from
    /// contending with itself on a single underlying queue.
    public func prewarm(limit: Int = 30) async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        await fetchRecentAssets(limit: limit)
        await loadAlbumsIfNeeded()
    }

    // MARK: - Recent assets

    /// Resolves auth state, requests if needed, then fetches and stores the
    /// most recent `limit` assets. Nonisolated async: awaiting hops to the
    /// cooperative pool; the heavy fetch runs off-main inside `PhotoLibraryService`.
    public func fetchRecentAssets(limit: Int = 30) async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        await MainActor.run { setAuthStatus(status) }

        if status != .authorized && status != .limited {
            await MainActor.run { clearRecentAssetsIfNeeded() }
        }

        switch status {
        case .authorized, .limited:
            let assets = await library.fetchRecentAssets(limit: limit)
            await MainActor.run { updateAssets(assets) }
        case .notDetermined:
            let granted = await library.requestAuthorization()
            await MainActor.run { setAuthStatus(granted) }
            if granted == .authorized || granted == .limited {
                let assets = await library.fetchRecentAssets(limit: limit)
                await MainActor.run { updateAssets(assets) }
            } else {
                await MainActor.run { clearRecentAssetsIfNeeded() }
            }
        default:
            await MainActor.run { clearRecentAssetsIfNeeded() }
        }
    }

    // MARK: - Albums

    /// Loads the album list if it hasn't been loaded yet. Idempotent.
    public func loadAlbumsIfNeeded() async {
        let needsLoad = await MainActor.run { albums.isEmpty }
        guard needsLoad else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        let fetched = await library.fetchAlbums()
        await MainActor.run { albums = fetched }
    }

    /// Force re-fetch of the album list. Called when PhotoKit reports a
    /// library change that might have added/removed albums.
    public func reloadAlbums() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            await MainActor.run { albums = [] }
            return
        }
        let fetched = await library.fetchAlbums()
        await MainActor.run { albums = fetched }
    }

    /// Fetch the assets contained in a specific album.
    public func fetchAssets(in album: PhotoLibraryService.AlbumInfo, limit: Int = 200) async -> [PHAsset] {
        await library.fetchAssets(in: album.collection, limit: limit)
    }

    // MARK: - UIKit-bridged picker presentations

    /// Opens the native Apple limited library picker. Touches UIKit; marked
    /// `@MainActor` so the call site is on the main thread.
    @MainActor
    public func openLimitedPicker() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        let topVC = findTopViewController(from: rootVC)

        if #available(iOS 15.0, *) {
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: topVC) { _ in
                Task { await self.fetchRecentAssets() }
            }
        } else {
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: topVC)
        }
    }

    /// Presents `PHPickerViewController` via UIKit (avoids SwiftUI sheet collisions).
    @MainActor
    public func openSystemPicker(selectionLimit: Int, completion: @escaping ([PHAsset]) -> Void) {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = selectionLimit
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = PhotoKitServicePickerDelegate.shared
        PhotoKitServicePickerDelegate.shared.completion = completion

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        let topVC = findTopViewController(from: rootVC)
        topVC.present(picker, animated: true)
    }

    // MARK: - Thumbnail loading
    //
    // Phase-1 carryover: thumbnail loading remains on the facade for now
    // because many existing views (cells, previewers) call it directly. Phase 2
    // will decide whether to route through per-cell view-models or keep it as
    // a documented exception. Behavior unchanged from before the rebuild.

    /// Loads a thumbnail for a given asset.
    /// Consults the process-wide `ThumbnailCache` first — on hit, `completion`
    /// runs synchronously inline so the caller can paint without an async hop.
    ///
    /// Cache hit only counts when the cached image's pixel dimensions are
    /// at least as large as `size`. A smaller-than-requested cached image
    /// triggers a refetch at the requested size, and the new (larger)
    /// image replaces it. Downstream callers asking for SMALLER sizes
    /// later read this larger cached image and downscale visually via
    /// `.scaledToFill()`. This single-largest-per-asset policy is what
    /// prevents the previewer from showing a blurry image after the grid
    /// cell had cached a small version (the original bug).
    public func loadThumbnail(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let key = ThumbnailCache.key(for: asset)

        if let cached = ThumbnailCache.shared.object(forKey: key),
           cached.pixelSize.width >= size.width,
           cached.pixelSize.height >= size.height {
            completion(cached)
            return
        }

        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat

        manager.requestImage(for: asset,
                             targetSize: size,
                             contentMode: .aspectFill,
                             options: options) { image, _ in
            if let image = image {
                // Guard against a late-arriving small fetch clobbering a
                // larger image that some other caller already cached. Only
                // replace when the incoming image is at least as large
                // (by area) as what's there.
                let existing = ThumbnailCache.shared.object(forKey: key)
                if existing == nil || image.pixelSize.area >= existing!.pixelSize.area {
                    ThumbnailCache.shared.setObject(image, forKey: key)
                }
            }
            completion(image)
        }
    }

    // MARK: - Private (state writers + UIKit helpers)

    /// Equality-guarded auth setter. `@Observable` instruments every setter
    /// call — writing the same value still notifies subscribers and cascades
    /// a re-eval (root cause of the flicker fixed in PR #7).
    @MainActor
    private func setAuthStatus(_ newStatus: PHAuthorizationStatus) {
        guard newStatus != authStatus else { return }
        authStatus = newStatus
    }

    @MainActor
    private func clearRecentAssetsIfNeeded() {
        guard !recentAssets.isEmpty else { return }
        recentAssets = []
    }

    /// Equality-guarded write path. Skips assignment when the identifier
    /// set hasn't actually changed so we don't cascade `@Observable`
    /// notifications and force a rebuild of every grid cell.
    @MainActor
    private func updateAssets(_ assets: [PHAsset]) {
        // Defensive: never shrink a populated list to empty.
        // PhotoKit's Limited Access selection set is briefly empty during
        // popup dismiss; we don't want recentAssets to flash blank either.
        if assets.isEmpty && !self.recentAssets.isEmpty { return }

        let newIDs = assets.map(\.localIdentifier)
        let oldIDs = self.recentAssets.map(\.localIdentifier)
        guard newIDs != oldIDs else { return }

        self.recentAssets = assets
    }

    @MainActor
    private func findTopViewController(from root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController {
            return findTopViewController(from: presented)
        }
        if let nav = root as? UINavigationController {
            return findTopViewController(from: nav.visibleViewController ?? nav)
        }
        if let tab = root as? UITabBarController {
            return findTopViewController(from: tab.selectedViewController ?? tab)
        }
        return root
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension PhotoKitService: PHPhotoLibraryChangeObserver {
    /// Sync nonisolated callback per Apple's protocol. Hops to MainActor via
    /// a Task to do the (now-async) refresh work.
    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.updateAuthStatus()

            // When using a fetchLimit, changeInstance.changeDetails(for:) is
            // unreliable and can miss newly inserted items or return nil.
            // We force a full refresh to guarantee the UI reflects the new state.
            if self.authStatus == .authorized || self.authStatus == .limited {
                await self.fetchRecentAssets()
            }
        }
    }
}

// MARK: - UIImage pixel-size helper (used by loadThumbnail size comparisons)

private extension UIImage {
    /// True pixel dimensions = points * scale. `UIImage.size` alone is in
    /// points, which lies on Retina devices (a 400×400 thumbnail @2x has
    /// `size == 200×200`); comparing that against a point-based requested
    /// size would always look "too small" and trigger needless refetches.
    var pixelSize: CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }
}

private extension CGSize {
    var area: CGFloat { width * height }
}

// MARK: - PHPickerViewControllerDelegate adapter

final class PhotoKitServicePickerDelegate: NSObject, PHPickerViewControllerDelegate {
    static let shared = PhotoKitServicePickerDelegate()
    var completion: (([PHAsset]) -> Void)?

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        let identifiers = results.compactMap(\.assetIdentifier)
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        completion?(assets)
    }
}
