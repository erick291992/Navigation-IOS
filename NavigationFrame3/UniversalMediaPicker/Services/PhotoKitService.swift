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

    /// Initial page size for the grid — how many PHAssets we mount on first
    /// paint. Deliberately small (~one viewport at a 4-column grid) so the
    /// cells that fire `.task` on initial mount don't pile 60 requests onto
    /// PhotoKit's serial queue at once. Pagination fills the rest as the
    /// user scrolls; off-screen cells aren't even mounted by LazyVGrid until
    /// they near the viewport, so the deferred cost is genuinely deferred.
    ///
    /// Used by both `prewarmVisibleContent` (step 1 fetch) and
    /// `AssetGridViewModel.loadAssets` (the bounded first fetch). Single
    /// source of truth — drift would mean prewarm caches a different set
    /// than the grid mounts.
    public static let gridInitialPageSize = 20

    /// How many of the initial-page cells to pre-decode into
    /// `ThumbnailCache.shared` during prewarm. Set equal to
    /// `gridInitialPageSize` so the ENTIRE initial page is cache-hit on
    /// sheet open — including the bottom row that sits just at the fold
    /// (cells 17-19 at a 4-column grid are visible in the initial
    /// viewport on many devices, so they need to be cache hits too).
    ///
    /// Must be ≤ `gridInitialPageSize`; we never try to prewarm a cell
    /// that wasn't fetched in step 1.
    public static let gridInitialPrewarmCount = 20

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
    ///
    /// `isNetworkAccessAllowed = true` lets PhotoKit fetch thumbnails for
    /// iCloud-only assets (common when the user has "Optimize iPhone
    /// Storage" enabled — older photos live only in iCloud with metadata
    /// stubs locally). Without it, `.highQualityFormat` returns nil for
    /// iCloud-only assets, and those cells render as empty black squares
    /// forever. Apple's Photos.app sets this for the same reason.
    @ObservationIgnored private let thumbnailRequestOptions: PHImageRequestOptions = {
        let opts = PHImageRequestOptions()
        opts.isSynchronous = false
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
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

    /// Cancellable handle for `prewarmVisibleContent`'s step 4 (grid-cell
    /// thumbnail prewarm). The modifier calls `cancelGridPrewarm()` from
    /// `.onChange(of: isPresented)` the moment the sheet is about to open
    /// — that way, if the user is fast enough to tap before step 4
    /// finishes (the cold-race case), the in-flight prewarm stops queuing
    /// new requests instead of competing with sheet-open's own PhotoKit
    /// requests. Touched only on `MainActor`.
    @ObservationIgnored private var gridPrewarmTask: Task<Void, Never>?

    /// Cancellable handle for the ENTIRE `prewarm()` pipeline — wraps
    /// recents fetch, albums fetch, AND the visible-content sequence
    /// (steps 1-4) in a single outer task. Set the moment `prewarm()` is
    /// called so the modifier's `cancelGridPrewarm()` can abort the work
    /// at ANY phase, including the early recents/albums fetches.
    ///
    /// Why the whole pipeline and not just visible-content: cold-race
    /// testing showed the cancel landing DURING the recents fetch (long
    /// before the visible-content task got spawned). Wrapping only
    /// visible-content meant the cancel found a nil handle and was a
    /// no-op; the rest of the pipeline ran to completion and raced
    /// sheet-open's own PhotoKit requests. With this outer task, the
    /// cancel always has something to bite, and `Task.isCancelled` checks
    /// between phases abort the remaining work cooperatively.
    @ObservationIgnored private var prewarmTask: Task<Void, Never>?

    /// Monotonic counter bumped at the start of every `prewarm()` call.
    /// Used so the cleanup-on-completion code knows whether to clear
    /// `prewarmTask` — only the most-recent call's generation matches
    /// the current value, so older completing calls don't clobber a
    /// newer in-flight task's handle. `Task` itself isn't
    /// identity-equatable in Swift, hence the counter.
    @ObservationIgnored private var prewarmGeneration: UInt64 = 0

    /// Set to `true` once `prewarmVisibleContent()` has completed a full
    /// pass (NOT cancelled). Subsequent `prewarm()` calls early-return on
    /// the visible-content phase, so it's safe for a consumer to call
    /// `PhotoKitService.shared.prewarm()` from BOTH an early site (App.init,
    /// scene root, etc.) AND have the modifier also invoke it — only the
    /// first complete pass does real work, the rest are no-ops.
    ///
    /// Stays `false` when `prewarmVisibleContent` is cancelled mid-flight
    /// (cold-race case) — the next `prewarm()` call will re-run the full
    /// sequence, since the cache may be only partially populated.
    ///
    /// Reset to `false` by `photoLibraryDidChange` so a library mutation
    /// (user took a photo, deleted one, edited Limited Access selection)
    /// invalidates the cached prewarm state and the next `prewarm()` call
    /// re-warms with fresh content. Touched only on `MainActor`.
    @ObservationIgnored private var hasPrewarmedVisibleContent: Bool = false

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

    // MARK: - Prewarm

    /// **Fire-and-forget background warming. Call once from `App.init`** for
    /// the fastest possible first picker open. One line — no async, no Task
    /// wrapping, no priority to remember at the call site.
    ///
    ///     @main
    ///     struct MyApp: App {
    ///         init() {
    ///             PhotoKitService.prewarm()
    ///         }
    ///         // ...
    ///     }
    ///
    /// Internally spawns a `.utility`-priority Task that calls the instance
    /// `prewarm()` method. The work is idempotent — safe to call alongside
    /// the modifier's own `.task` prewarm; the second caller becomes a
    /// no-op via the `hasPrewarmedVisibleContent` flag.
    ///
    /// Why static and fire-and-forget: callers don't need to think about
    /// `Task { ... }`, `await`, or `priority: .utility`. The right thing
    /// happens automatically. Picker module users only need one line in
    /// `App.init` to get the full warming benefit.
    public static func prewarm() {
        // Priority is set on the inner Task inside the instance method,
        // so we don't need to set it here — both the static path and the
        // modifier's `await prewarm()` path end up at `.utility`.
        Task {
            await shared.prewarm()
        }
    }

    /// Async entry point for callers that need explicit lifecycle control
    /// (e.g. `MediaPickerModifier`'s `.task` awaits this so its body
    /// completes after warming finishes). Same idempotent pipeline as the
    /// static `prewarm()` — they share the same body.
    ///
    /// Sequential phases (each one feeds the next):
    ///   1. `fetchRecentAssets` — populates `recentAssets` (PHAsset refs)
    ///   2. `loadAlbumsIfNeeded` — populates `albums` (PHAssetCollection refs)
    ///   3. `prewarmVisibleContent` — pre-fetches the first album's grid
    ///      page, primes PhotoKit's pool via `setCachedAssets`, and
    ///      pre-decodes the first 20 cells into `ThumbnailCache.shared`.
    ///
    /// Does NOT prompt for authorization — first-time users hit the auth
    /// prompt at their intent moment (when they actually open the picker).
    ///
    /// **Idempotent.** Safe to call from multiple entry points (e.g.
    /// `App.init` via the static, AND the modifier's `.task`) — only the
    /// first complete pass does real work. Subsequent calls early-return
    /// on the visible-content phase. A library mutation
    /// (`photoLibraryDidChange`) resets the flag so the next call after
    /// the mutation re-warms with fresh content.
    public func prewarm() async {
        // Wrap the whole pipeline in an unstructured Task stored as
        // `prewarmTask` so the modifier's `cancelGridPrewarm()` can abort
        // the work at ANY phase — including the early recents/albums
        // fetches that happen BEFORE the visible-content steps even
        // start. The Task handle exists from the very first PhotoKit call
        // (unlike the old design where it was set after recents+albums).
        let generation = await MainActor.run {
            self.prewarmGeneration &+= 1
            return self.prewarmGeneration
        }
        // `priority: .utility` tells the OS scheduler this is background
        // work that should yield to UI events. Without this, prewarm runs
        // at the default priority and competes with sheet animation /
        // button taps for main-thread frames — making the picker feel
        // unresponsive at the moment the user actually wants it. Set on
        // the INNER task (not the static wrapper) so both the App.init
        // and modifier entry points get the same priority.
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.performPrewarm()
        }
        await MainActor.run { self.prewarmTask = task }
        await task.value
        await MainActor.run {
            // Clear only if a newer `prewarm()` call hasn't replaced our
            // entry while we were awaiting (compared via the monotonic
            // generation counter — `Task` itself isn't identity-equatable).
            if self.prewarmGeneration == generation {
                self.prewarmTask = nil
            }
        }
    }

    /// The actual body of `prewarm()`. Lives in its own method so the
    /// outer `prewarm()` can wrap it in a cancellable Task. Every phase
    /// boundary checks `Task.isCancelled` — when the modifier cancels
    /// `prewarmTask` mid-pipeline, the next boundary aborts cooperatively.
    private func performPrewarm() async {
        PickerPerfLog.event("photoKit.prewarm → enter")
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            PickerPerfLog.event("photoKit.prewarm → skipped (no auth)")
            return
        }
        // Note: `fetchRecentAssets` and `loadAlbumsIfNeeded` are already
        // individually idempotent (coalescer + `needsLoad` guard). The
        // visible-content phase has its own flag-based idempotency below.
        //
        // The `await` calls here will run to completion even after our
        // outer task is cancelled — they're either coalesced shared tasks
        // (`fetchRecentAssets`) or one-shot fetches feeding observable
        // state the picker UI needs regardless. We check `Task.isCancelled`
        // AFTER each await to decide whether to continue the pipeline.
        // `limit: 1` because the main picker's only consumer of
        // `recentAssets` is the LibraryViewfinder's "is library empty?"
        // check. The previewer follows the album's first asset via
        // `prewarmedFirstAlbumAssets`, not `recentAssets`. Other callers
        // (e.g. `EliteGeometricPickerViewModel`) use `fetchRecentAssets`
        // directly with their own limit and don't go through prewarm.
        await fetchRecentAssets(limit: 1)
        if Task.isCancelled {
            PickerPerfLog.event("photoKit.prewarm → cancelled after recents")
            return
        }
        PickerPerfLog.event("photoKit.prewarm → recents loaded (\(recentAssets.count))")

        await loadAlbumsIfNeeded()
        if Task.isCancelled {
            PickerPerfLog.event("photoKit.prewarm → cancelled after albums")
            return
        }
        PickerPerfLog.event("photoKit.prewarm → albums loaded (\(albums.count))")

        // Idempotency check: skip the visible-content phase if a previous
        // `prewarm()` call already completed it AND no library mutation has
        // invalidated the cache since. Lets consumers safely call
        // `prewarm()` from BOTH App.init (via the static) AND the
        // modifier's `.task` without doing the work twice.
        let alreadyWarm = await MainActor.run { self.hasPrewarmedVisibleContent }
        if alreadyWarm {
            PickerPerfLog.event("photoKit.prewarm → visible content already warm, skipping")
            return
        }

        await prewarmVisibleContent()

        // Only flag as "warm" if the sequence wasn't cancelled mid-flight.
        // A cancelled prewarm may have populated only a subset of the
        // cache (e.g. step 2 but not step 4) — the next `prewarm()` call
        // needs to re-run the remaining steps.
        if Task.isCancelled {
            PickerPerfLog.event("photoKit.prewarm → cancelled (skipping warm flag)")
            return
        }
        await MainActor.run { self.hasPrewarmedVisibleContent = true }
    }

    /// Pre-fetch the first album's grid page (20 PHAssets, top-K path) AND
    /// pre-decode the first ~20 grid cells into `ThumbnailCache`. Called
    /// as the third phase of `prewarm`.
    ///
    /// Sequential is intentional — same lesson as the picker's own
    /// `bootstrap()`: running these in parallel via `async let` would
    /// pile multiple PhotoKit requests onto the serial queue at once and
    /// risk contending with other work. Sequential keeps the queue clean.
    ///
    /// **Previewer 1000pt warm AND gallery shortcut 140pt warm used to
    /// run here too** (between the page fetch and step 4). Both removed
    /// because under the cold-race scenario, in-flight decodes can't be
    /// aborted by `Task.cancel()` and hog PhotoKit's serial queue while
    /// the sheet is trying to open — making the tap feel dead. The
    /// previewer + gallery shortcut now do their own async loads when
    /// they mount (~100ms previewer, ~15ms shortcut, both cheap because
    /// PhotoKit's pool is still warmed by `setCachedAssets`). Net trade:
    /// previewer/shortcut go from "instant on warm-prewarm path" to
    /// "always ~15-100ms," cells stop getting blocked, sheet opens
    /// responsively. Deterministic over best-case-but-sometimes-bad.
    private func prewarmVisibleContent() async {
        PickerPerfLog.event("photoKit.prewarm.visible → start")

        let firstAlbum: PhotoLibraryService.AlbumInfo? = await MainActor.run { self.albums.first }

        guard let firstAlbum else {
            PickerPerfLog.event("photoKit.prewarm.visible → skipped (no album)")
            return
        }

        // 1. Pre-fetch first album's grid page using PhotoKit's top-K
        //    fast path. Store the result on `prewarmedFirstAlbumAssets`
        //    so `AssetGridViewModel.init` can read it synchronously and
        //    mount with cells already populated.
        let firstPage = await library.fetchAssets(in: firstAlbum.collection, limit: Self.gridInitialPageSize)
        await MainActor.run {
            setCachedAssets(firstPage, targetSize: Self.gridThumbnailTargetSize)
            self.prewarmedFirstAlbumAssets = firstPage
        }
        PickerPerfLog.event("photoKit.prewarm.visible → first album fetched + warmed (\(firstPage.count))")

        if Task.isCancelled {
            PickerPerfLog.event("photoKit.prewarm.visible → cancelled before step 4")
            return
        }

        guard firstPage.first != nil else {
            // Album is empty — no cells to prewarm. Grid prewarm in step 4
            // would also be a no-op; skip the rest.
            PickerPerfLog.event("photoKit.prewarm.visible → skipped further steps (album empty)")
            return
        }

        // 4. Pre-decode the first ~20 grid cells (one viewport's worth)
        //    into ThumbnailCache.shared so the grid paints its visible
        //    viewport instantly when the sheet opens.
        //
        //    Stored as a cancellable Task so the modifier can abort it
        //    via cancelGridPrewarm() the moment the sheet is about to
        //    present — that's the cold-race protection. Task.isCancelled
        //    is checked between requests; PhotoKit's in-flight work isn't
        //    abortable, but no further requests get queued.
        let primeCount = min(Self.gridInitialPrewarmCount, firstPage.count)
        guard primeCount > 0 else {
            PickerPerfLog.event("photoKit.prewarm.visible → step 4 skipped (no cells)")
            return
        }
        PickerPerfLog.event("photoKit.prewarm.visible → step 4 start (\(primeCount) cells)")

        let prewarmTask = Task { [weak self] in
            guard let self else { return }
            for asset in firstPage.prefix(primeCount) {
                if Task.isCancelled {
                    PickerPerfLog.event("photoKit.prewarm.visible → step 4 cancelled")
                    return
                }
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.loadThumbnail(for: asset, size: Self.gridThumbnailTargetSize) { _ in
                        continuation.resume()
                    }
                }
            }
            PickerPerfLog.event("photoKit.prewarm.visible → step 4 done")
        }
        await MainActor.run { self.gridPrewarmTask = prewarmTask }
        await prewarmTask.value
        await MainActor.run { self.gridPrewarmTask = nil }
    }

    /// Cancels any in-flight `prewarm()` pipeline — both the outer
    /// `prewarmTask` (which wraps the whole recents → albums →
    /// visible-content sequence) AND the inner `gridPrewarmTask` (step 4
    /// per-cell work). Called from `MediaPickerModifier`'s
    /// `.onChange(of: isPresented)` when the sheet is about to open, so
    /// in-flight prewarm doesn't compete with sheet-open's own PhotoKit
    /// requests during the cold-race scenario (user taps before prewarm
    /// finishes). No-op if prewarm has already completed or never ran.
    ///
    /// **Why cancel both tasks**: timing-dependent. The cancel can land
    /// during recents/albums fetch (prewarmTask aborts at the next
    /// `Task.isCancelled` check), during visible-content steps 1-3
    /// (prewarmTask aborts at the inter-step check), or during step 4
    /// (gridPrewarmTask's per-iteration check stops queuing new
    /// requests). Cancelling both covers all three windows. Cancelling
    /// only `gridPrewarmTask` (the original design) missed cancels that
    /// landed in the earlier phases.
    @MainActor
    public func cancelGridPrewarm() {
        prewarmTask?.cancel()
        prewarmTask = nil
        gridPrewarmTask?.cancel()
        gridPrewarmTask = nil
    }

    /// Decodes the given PHAssets' thumbnails into `ThumbnailCache.shared`
    /// at the grid's target size. Sequential through PhotoKit's serial
    /// queue; honors `Task.isCancelled` between requests so the caller can
    /// abort partway through (e.g. rapid album switching supersedes the
    /// prewarm for the previous album).
    ///
    /// Used by:
    /// - `prewarmVisibleContent` step 4 (cold-open prewarm in modifier idle)
    /// - `AssetGridViewModel.loadAssets` (album-switch prewarm before the
    ///   visible swap, so the new album reveals with a populated viewport
    ///   instead of empty squares trickling in)
    public func prewarmGridCells(_ assets: some Collection<PHAsset>) async {
        for asset in assets {
            if Task.isCancelled { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                loadThumbnail(for: asset, size: Self.gridThumbnailTargetSize) { _ in
                    continuation.resume()
                }
            }
        }
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
    /// was configured with. Most call sites use the default (1), so divergence
    /// is rare; `EliteGeometricPickerViewModel` is the explicit exception that
    /// requests a larger limit because its grid is built from `recentAssets`.
    public func fetchRecentAssets(limit: Int = 1) async {
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

            // Invalidate the prewarm-completion flag so the next `prewarm()`
            // call re-warms with fresh content. The library mutated — our
            // cached `prewarmedFirstAlbumAssets` + ThumbnailCache entries
            // may be stale (user took a photo, deleted one, edited Limited
            // Access selection).
            self.hasPrewarmedVisibleContent = false

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
