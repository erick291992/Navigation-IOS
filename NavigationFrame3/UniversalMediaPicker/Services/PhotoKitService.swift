import Foundation
import Photos
import PhotosUI
import UIKit
import Observation

/// Process-wide thumbnail cache. Keys include `modificationDate` so an
/// in-place edit in `Photos.app` (crop, markup, filter — same identifier,
/// new pixels) produces a cache miss and a fresh fetch. Without this, the
/// grid would happily serve pre-edit pixels until the entry was evicted.
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

    /// Warms the recent-assets cache when authorization is already granted.
    /// Does NOT prompt — first-time users hit the auth prompt at their
    /// intent moment (when they actually open the picker).
    public func prewarm(limit: Int = 30) async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        await fetchRecentAssets(limit: limit)
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
    public func loadThumbnail(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let key = ThumbnailCache.key(for: asset)
        if let cached = ThumbnailCache.shared.object(forKey: key) {
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
                ThumbnailCache.shared.setObject(image, forKey: key)
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
