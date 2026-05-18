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
    public static let shared = PhotoKitService()

    /// Pixel size grid cells render thumbnails at. Single source of truth so
    /// the prewarm size (in `setCachedAssets`) and the cell's request size
    /// (in `AssetThumbnailCell`) cannot drift apart — a mismatch silently
    /// misses PhotoKit's warm pool and reintroduces the cold-start lag.
    public static let gridThumbnailTargetSize = CGSize(width: 400, height: 400)

    /// Pixel size the library viewfinder's previewer requests. Larger than
    /// the grid size so the top image is sharp at the ~48% viewfinder
    /// height. Lives here as a constant so the previewer VM and any future
    /// previewer prewarm reference the same number.
    public static let previewerTargetSize = CGSize(width: 1000, height: 1000)

    public var recentAssets: [PHAsset] = []
    public var authStatus: PHAuthorizationStatus = .notDetermined
    public var albums: [PhotoLibraryService.AlbumInfo] = []

    /// First album's pre-fetched 60 PHAssets, populated by `prewarmVisibleContent`.
    /// `AssetGridViewModel.init` reads this so the grid mounts with cells
    /// already populated — no empty-state flash, no async wait for the picker's
    /// own `loadAssets` to fire. When prewarm hasn't completed yet (cold race),
    /// this is empty and the grid's own async fetch fills it normally.
    public var prewarmedFirstAlbumAssets: [PHAsset] = []

    private let library = PhotoLibraryService.shared

    /// PhotoKit's prefetcher. Tell it "I'm about to ask for these N assets
    /// at this size" via `startCachingImages`; subsequent `requestImage`
    /// calls at the same key return from the warm pool instead of going to
    /// disk. Not a parallel image cache — `ThumbnailCache` above is the
    /// in-process bitmap cache; this one lives inside PhotoKit and is
    /// managed by Apple (eviction, memory pressure, etc.).
    @ObservationIgnored private let cachingManager = PHCachingImageManager()

    /// Reused by both `startCachingImages` (prewarm) and `requestImage`
    /// (per-cell read) so PhotoKit treats the warm and the read as the same
    /// request shape — drift here silently misses the warm pool.
    @ObservationIgnored private let thumbnailRequestOptions: PHImageRequestOptions = {
        let opts = PHImageRequestOptions()
        opts.isSynchronous = false
        opts.deliveryMode = .highQualityFormat
        return opts
    }()

    /// Tracks what's currently being warmed so the next call can stop the
    /// old set before starting the new one. `@MainActor`-touched only —
    /// `setCachedAssets` is `@MainActor` and is the sole writer.
    @ObservationIgnored private var cachedAssets: [PHAsset] = []
    @ObservationIgnored private var cachedSize: CGSize = .zero

    /// In-flight `fetchRecentAssets` handle for coalescing. When multiple
    /// callers race (e.g. `openLimitedPicker` completion + library change
    /// observer firing back-to-back), the second and later callers await
    /// the first caller's Task instead of issuing redundant PhotoKit
    /// requests. Touched only on `MainActor` (check/store + clear).
    @ObservationIgnored private var inFlightRecentsFetch: Task<Void, Never>?

    /// Nonisolated — init does only thread-safe PhotoKit calls
    /// (`authorizationStatus(for:)` and `register(_:)` are both documented
    /// thread-safe) plus one write to `authStatus` before the instance is
    /// observable by anyone. Removing the `@MainActor` here lets
    /// `MediaPickerManager` (and any other consumer) hold a reference to
    /// `PhotoKitService.shared` from a nonisolated context.
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

    /// Warms the picker's full sheet-open state when authorization is
    /// already granted. Does NOT prompt — first-time users hit the auth
    /// prompt at their intent moment (when they actually open the picker).
    ///
    /// Sequential phases (each one feeds the next):
    ///   1. `fetchRecentAssets` — populates `recentAssets` (PHAsset refs)
    ///   2. `loadAlbumsIfNeeded` — populates `albums` (PHAssetCollection refs)
    ///   3. (if `warmVisibleContent`) `prewarmVisibleContent` —
    ///      pre-fetches the first album's grid page + pre-loads the
    ///      library previewer's 1000pt bitmap + gallery shortcut's 140pt
    ///      bitmap into `ThumbnailCache`.
    ///
    /// Phase 3 moves the cold-PhotoKit cost OFF the picker's sheet-open
    /// critical path and ONTO the modifier-host's view appearance, which
    /// typically gives the user 1-3+ seconds to navigate before tapping
    /// "open picker." When they tap, PhotoKit is fully warm: grid fetch
    /// returns from internal cache, previewer + gallery shortcut paint
    /// synchronously from `ThumbnailCache`.
    ///
    /// `warmVisibleContent: false` is the opt-out for callers that want
    /// only metadata warming (rare).
    public func prewarm(limit: Int = 30, warmVisibleContent: Bool = true) async {
        PickerPerfLog.event("photoKit.prewarm → enter")
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            PickerPerfLog.event("photoKit.prewarm → skipped (no auth)")
            return
        }
        await fetchRecentAssets(limit: limit)
        PickerPerfLog.event("photoKit.prewarm → recents loaded (\(recentAssets.count))")
        await loadAlbumsIfNeeded()
        PickerPerfLog.event("photoKit.prewarm → albums loaded (\(albums.count))")

        guard warmVisibleContent else { return }
        await prewarmVisibleContent()
    }

    /// Pre-fetch the first album's grid page (60 PHAssets, top-K path) AND
    /// pre-load the library previewer's 1000pt bitmap AND pre-load the
    /// gallery shortcut's 140pt bitmap into `ThumbnailCache`. Called as the
    /// third phase of `prewarm` by default.
    ///
    /// Sequential is intentional — same lesson as the picker's own
    /// `bootstrap()`: running these in parallel via `async let` would
    /// pile multiple PhotoKit requests onto the serial queue at once and
    /// risk contending with other work. Sequential keeps the queue clean.
    private func prewarmVisibleContent() async {
        PickerPerfLog.event("photoKit.prewarm.visible → start")

        let firstAlbum: PhotoLibraryService.AlbumInfo? = await MainActor.run { self.albums.first }
        let recentFirst: PHAsset? = await MainActor.run { self.recentAssets.first }

        guard let firstAlbum, let recentFirst else {
            PickerPerfLog.event("photoKit.prewarm.visible → skipped (no album or recent)")
            return
        }

        // 1. Pre-fetch first album's grid page using PhotoKit's top-K
        //    fast path. Store the result on `prewarmedFirstAlbumAssets`
        //    so `AssetGridViewModel.init` can read it synchronously and
        //    mount with cells already populated.
        let firstPage = await library.fetchAssets(in: firstAlbum.collection, limit: 60)
        await MainActor.run {
            setCachedAssets(firstPage, targetSize: Self.gridThumbnailTargetSize)
            self.prewarmedFirstAlbumAssets = firstPage
        }
        PickerPerfLog.event("photoKit.prewarm.visible → first album fetched + warmed (\(firstPage.count))")

        // 2. Pre-load library previewer's 1000pt bitmap into ThumbnailCache.
        //    When the picker mounts, LibraryViewfinderViewModel.thumbnail(for:)
        //    peeks the cache synchronously and paints on the first frame.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loadThumbnail(for: recentFirst, size: Self.previewerTargetSize) { _ in
                continuation.resume()
            }
        }
        PickerPerfLog.event("photoKit.prewarm.visible → previewer 1000pt warmed")

        // 3. Pre-load gallery shortcut's 140pt bitmap. ThumbnailCache's
        //    largest-wins policy means this usually returns from the 1000pt
        //    cache hit above (downscaled visually by SwiftUI) — but we still
        //    issue the request to populate any size-specific PhotoKit caches.
        let galleryThumbSize = CGSize(width: 140, height: 140)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loadThumbnail(for: recentFirst, size: galleryThumbSize) { _ in
                continuation.resume()
            }
        }
        PickerPerfLog.event("photoKit.prewarm.visible → gallery thumb 140pt warmed")
    }

    // MARK: - Recent assets

    /// Resolves auth state, requests if needed, then fetches and stores the
    /// most recent `limit` assets. Nonisolated async: awaiting hops to the
    /// cooperative pool; the heavy fetch runs off-main inside `PhotoLibraryService`.
    ///
    /// **Coalesced.** Concurrent callers (e.g. `openLimitedPicker` completion
    /// firing alongside `photoLibraryDidChange`) await a single shared Task
    /// instead of issuing redundant PhotoKit fetches. The first caller's
    /// `limit` wins — subsequent callers receive whatever the in-flight fetch
    /// was configured with. In practice every call site uses `limit: 30`
    /// (default), so divergence is theoretical.
    public func fetchRecentAssets(limit: Int = 30) async {
        let task: Task<Void, Never> = await MainActor.run {
            if let existing = inFlightRecentsFetch {
                return existing
            }
            let newTask = Task { [weak self] in
                guard let self else { return }
                await self.performRecentAssetsFetch(limit: limit)
                await MainActor.run { self.inFlightRecentsFetch = nil }
            }
            inFlightRecentsFetch = newTask
            return newTask
        }
        await task.value
    }

    private func performRecentAssetsFetch(limit: Int) async {
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
    /// **Prefer the paginated pair** (`fetchAssetsResult(in:)` +
    /// `materialize(from:range:)`) for the grid — see those methods below.
    public func fetchAssets(in album: PhotoLibraryService.AlbumInfo, limit: Int = 200) async -> [PHAsset] {
        await library.fetchAssets(in: album.collection, limit: limit)
    }

    /// Facade for `PhotoLibraryService.fetchAssetsResult` — see that method
    /// for the rationale on returning the lazy `PHFetchResult` instead of an
    /// eager array. Used by `AssetGridViewModel` to paginate the grid.
    public func fetchAssetsResult(in album: PhotoLibraryService.AlbumInfo) async -> PHFetchResult<PHAsset> {
        await library.fetchAssetsResult(in: album.collection)
    }

    /// Facade for `PhotoLibraryService.materialize` — used to incrementally
    /// pull batches of `PHAsset` out of a previously-fetched result.
    public func materialize(
        from result: PHFetchResult<PHAsset>,
        range: Range<Int>
    ) async -> [PHAsset] {
        await library.materialize(from: result, range: range)
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

    // MARK: - Thumbnail loading
    //
    // Lane discipline: only view models call these. Views take their image
    // data as parameters from their parent's VM. The only UIKit-bridged
    // surface that survives in this service is `openLimitedPicker`, because
    // PhotoKit's manage-access picker has no SwiftUI equivalent.

    /// Synchronous peek into the process-wide `ThumbnailCache`. The grid VM
    /// passes the result to each cell as `initialImage` so the cell paints
    /// on its first frame without an async hop (and survives recycles where
    /// `@State` resets but the cache still holds the bitmap).
    ///
    /// Returns nil on miss; callers should kick off an async `loadThumbnail`
    /// to populate (which the cell's `.task(id:)` does automatically).
    public func cachedThumbnail(for asset: PHAsset) -> UIImage? {
        ThumbnailCache.shared.object(forKey: ThumbnailCache.key(for: asset))
    }

    /// Tells PhotoKit to start preparing thumbnails for `assets` at
    /// `targetSize` and to stop preparing the previously-warmed set.
    /// Call this immediately after an album's asset list arrives, before
    /// SwiftUI lays out cells — by the time cells call `loadThumbnail`,
    /// PhotoKit returns from its warm pool instead of doing a disk read +
    /// decode + resize (which is the ~400–1000 ms per-cell cold start the
    /// grid otherwise pays).
    ///
    /// No-op when the asset IDs and size match the currently-warmed set,
    /// so safe to call on every `loadAssets` invocation even when the
    /// observer fires repeatedly.
    @MainActor
    public func setCachedAssets(_ assets: [PHAsset], targetSize: CGSize) {
        let newIDs = assets.map(\.localIdentifier)
        let oldIDs = cachedAssets.map(\.localIdentifier)
        if newIDs == oldIDs && targetSize == cachedSize { return }

        if !cachedAssets.isEmpty {
            cachingManager.stopCachingImages(
                for: cachedAssets,
                targetSize: cachedSize,
                contentMode: .aspectFill,
                options: thumbnailRequestOptions
            )
        }
        if !assets.isEmpty {
            cachingManager.startCachingImages(
                for: assets,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: thumbnailRequestOptions
            )
        }
        cachedAssets = assets
        cachedSize = targetSize
    }

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
    ///
    /// Routed through `cachingManager` (not `PHImageManager.default()`)
    /// so requests at the prewarmed size hit PhotoKit's warm pool. Sizes
    /// that weren't prewarmed (e.g. the previewer's 1000pt) fall through
    /// to a normal fetch with no penalty.
    public func loadThumbnail(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let key = ThumbnailCache.key(for: asset)

        if let cached = ThumbnailCache.shared.object(forKey: key),
           cached.pixelSize.width >= size.width,
           cached.pixelSize.height >= size.height {
            completion(cached)
            return
        }

        cachingManager.requestImage(for: asset,
                                    targetSize: size,
                                    contentMode: .aspectFill,
                                    options: thumbnailRequestOptions) { image, _ in
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
    /// a re-eval through every view that observes `authStatus`, which has
    /// caused visible flicker when `PHPhotoLibraryChangeObserver` fires
    /// rapidly during normal library activity.
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
