import SwiftUI
import Photos
import Observation

// MARK: - Actions
public enum AssetGridAction {
    case loadInitialData
    case loadHistory([MediaItem])
    case selectAlbum(PhotoLibraryService.AlbumInfo)
    case selectAsset(GridAsset)
    case toggleAssetSelection(GridAsset)
    case clearSelection
}

// MARK: - State Lens
//
// `currentAlbum` and `albums` are NOT stored here. They're owned by
// `PickerViewModel` (the picker-level coordinator) and flow into
// `AssetGridView` via `@Binding` — Apple's `Picker(selection:)` pattern.
// The grid VM itself is concerned only with the assets it's been told to
// load and the user's selection state.
public struct AssetGridState {
    public var assets: [GridAsset] = []
    public var selectedAssets: [GridAsset] = [] // Ordered for numbered badges
    public var isLoading: Bool = false
}

// MARK: - ViewModel
//
// `@MainActor` at the class level — matches the picker's other view models.
// Every method (including async ones) is MainActor-isolated, so observable
// state writes happen on MainActor by construction. Async methods that await
// non-isolated service functions (PhotoKitService is not @MainActor) still
// hop off-main per SE-0338; control returns to MainActor on resume.
//
// **Selection survives SwiftUI churn via `AssetGridSelectionCache`** — a
// small process-wide cache that holds ONLY the user's selection
// (`[GridAsset]`). On `init`, the VM restores selection from the cache; on
// every selection mutation, the VM writes through to the cache. The VM
// instance itself is NOT cached — `AssetGridView` creates a fresh one each
// time via plain `@State`. The grid's loaded `assetGridState.assets` is also not
// cached (PhotoKit re-fetches are fast; skeleton UI bridges the brief
// reload). See `AssetGridSelectionCache.swift` for the full rationale.
@MainActor
@Observable
public final class AssetGridViewModel: NSObject {
    private let photoKitService: PhotoKitService
    public let selectionLimit: Int

    public var assetGridState = AssetGridState()

    /// Internal cache of the album most recently passed to `.selectAlbum` /
    /// `.loadInitialData`. Used only by the PhotoKit change observer's
    /// refresh path so it knows which album to re-fetch. Not exposed; not
    /// `@Observable`; views never see it.
    @ObservationIgnored private var lastLoadedAlbum: PhotoLibraryService.AlbumInfo?

    // MARK: - Pagination state
    //
    // The grid uses a **lazy two-phase fetch** model:
    //
    // PHASE 1 (on the critical path) — `fetchAssets(in:, limit: pageSize)`
    //   returns the first page eagerly. This call uses PhotoKit's top-K
    //   fast path (because of the `fetchLimit`), which is dramatically
    //   faster than an unbounded fetch on large libraries because PhotoKit
    //   doesn't have to establish the full sort order over the entire
    //   library — it only needs to find the top N most recent.
    //
    // PHASE 2 (lazy, triggered by user intent) — when the user scrolls to
    //   the pagination sentinel for the first time, `loadNextPageCore`
    //   kicks off an unbounded `fetchAssetsResult` Task and awaits it.
    //   The unbounded sort PhotoKit does here is expensive (~500-1000ms on
    //   a 33k-photo library) AND it monopolizes PhotoKit's serial queue.
    //
    // **Why lazy and not eager-in-background?** We tried firing PHASE 2
    // immediately after PHASE 1 (eager-background). On a real device with
    // a large library, the unbounded sort competed with the library
    // previewer's 1000pt image fetch and the gallery shortcut's 140pt
    // fetch on PhotoKit's serial queue, delaying those visible-to-user
    // images by 100-300ms. By deferring PHASE 2 until the user actually
    // scrolls past page 1, PhotoKit's queue stays free during sheet-open
    // and the visible content paints as fast as the pre-pagination
    // baseline. The first scroll past 60 pays the PHASE 2 cost once.
    //
    // See CODING_GUIDELINES.md §3 for the queue-contention lesson and the
    // canonical "do less near sheet-mount" rule.

    @ObservationIgnored private var fetchResult: PHFetchResult<PHAsset>?
    @ObservationIgnored private var isLoadingPage = false   // re-entry guard for loadNextPage

    /// PHASE 2 background fetch handle. `loadNextPageCore` awaits this if
    /// the user scrolls past the first page before the unbounded fetch
    /// completes. Cancelled via the `tasks` array on deinit.
    @ObservationIgnored private var pendingFullFetch: Task<Void, Never>?

    /// In-flight `loadAssets` task for the current album. When the user
    /// switches albums (or rapid-taps multiple albums in succession), each
    /// new selection cancels this so the previous album's prewarm + swap
    /// doesn't race with the new one. Tracked in `tasks` too so deinit
    /// cancels it.
    @ObservationIgnored private var loadAssetsTask: Task<Void, Never>?

    /// Pagination batch size — used for every page AFTER the first. Larger
    /// than the initial page so deep scrolling doesn't trigger pagination
    /// every other row. The initial page size lives on `PhotoKitService`
    /// (`gridInitialPageSize`) because the prewarm references it too.
    private static let paginationPageSize = 60

    /// How many cells before the end of the materialized list to start
    /// loading the next page. 4 cells = 1 row of buffer at a 4-column grid
    /// — small enough that the sentinel lives just past the initial 20-cell
    /// viewport (not inside it), large enough to give PhotoKit a row of
    /// lead time before the user actually scrolls to the bottom.
    private static let sentinelBuffer = 4

    // MARK: - Fire-and-forget task storage
    //
    // Pagination calls are sync (so the sentinel `.onAppear` in the view
    // can call `vm.loadNextPageIfNeeded()` without ceremony). We retain the
    // spawned Tasks here and cancel them on deinit so a mid-scroll dismiss
    // doesn't leak self-references or zombie work.

    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    public init(selectionLimit: Int = 1, photoKitService: PhotoKitService = .shared) {
        self.selectionLimit = selectionLimit
        self.photoKitService = photoKitService
        super.init()
        // Restore selection from the cache so user-tapped photos survive
        // SwiftUI's upstream identity churn (see AssetGridSelectionCache).
        assetGridState.selectedAssets = AssetGridSelectionCache.selection(for: selectionLimit)

        // Eager-init from the prewarmed singleton cache. When the modifier's
        // prewarm.visible has already pre-fetched the first album's 60
        // PHAssets, mount the grid with them immediately — no empty-state
        // flash, no async wait for `loadAssets`. When prewarm hasn't
        // completed (cold race), this is empty and the normal async path
        // (selectAlbum → loadAssets) fills it.
        //
        // **Also set `lastLoadedAlbum`** so `loadNextPageCore` and the
        // PHPhotoLibraryChangeObserver refresh path work for this initial
        // album. SwiftUI's `.onChange(of: currentAlbum)` only fires on
        // CHANGES, never on the initial value — so without setting
        // `lastLoadedAlbum` here, the trigger(.selectAlbum) chain that
        // normally populates it would never fire, leaving pagination and
        // library-change refreshes broken for the initial album.
        let prewarmed = photoKitService.prewarmedFirstAlbumAssets
        if !prewarmed.isEmpty, let firstAlbum = photoKitService.albums.first {
            assetGridState.assets = prewarmed.map { .phAsset($0) }
            lastLoadedAlbum = firstAlbum
        }

        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        tasks.forEach { $0.cancel() }
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - Pagination sentinel (read by AssetGridView's per-cell .onAppear)

    /// The id of the cell whose appearance should trigger the next page
    /// load. Sits `sentinelBuffer` cells before the end of the materialized
    /// list. Computed in the VM so the view stays dumb — it just compares
    /// `asset.id == sentinelAssetID` (O(1)) and fires `loadNextPageIfNeeded()`.
    public var sentinelAssetID: String? {
        let count = assetGridState.assets.count
        guard count > 0 else { return nil }
        let sentinelIndex = max(0, count - Self.sentinelBuffer)
        return assetGridState.assets[sentinelIndex].id
    }

    // MARK: - Session lifecycle

    /// Static convenience for callers that don't have a VM instance handy
    /// (e.g., `MediaPickerModifier`'s `.sheet(onDismiss:)`). Clears the
    /// selection cache directly without needing to construct a VM. The
    /// cache type itself is internal — only the VM (or its statics) touch
    /// it, satisfying the strict "view never touches the cache" rule.
    public static func clearSession(for selectionLimit: Int) {
        AssetGridSelectionCache.clear(for: selectionLimit)
    }

    // MARK: - Triggers (the only public mutation surface for the view)

    public func trigger(_ action: AssetGridAction) {
        switch action {
        case .loadInitialData:
            // Used by standalone consumers (e.g., AdvancedPickerExampleViewModel
            // in the demos) that don't manage `currentAlbum` externally — we
            // bootstrap by loading the first album internally.
            //
            // In the picker flow, `PickerView` owns `currentAlbum` and writes
            // it via the binding, which triggers `.selectAlbum` from
            // `AssetGridView`'s `.onChange`. This path is the demo fallback.
            Task { await loadInitialAlbum() }

        case .loadHistory(let items):
            assetGridState.assets = [] // Clear instantly to prevent "Ghost Library" flashes
            Task {
                let assets = items.map { GridAsset.mediaItem($0) }
                assetGridState.assets = assets
            }

        case .selectAlbum(let album):
            lastLoadedAlbum = album
            // Cancel any prior album-load (rapid-tap supersedes): the
            // previous album's prewarm + swap would otherwise race with
            // the new one, leaving the grid in an inconsistent state.
            loadAssetsTask?.cancel()
            let task = Task { [weak self] in
                guard let self else { return }
                await self.loadAssets(for: album)
            }
            loadAssetsTask = task
            tasks.append(task)

        case .selectAsset(let asset):
            if selectionLimit > 1 {
                toggleAssetSelection(asset)
            } else {
                writeSelection([asset])
            }

        case .toggleAssetSelection(let asset):
            toggleAssetSelection(asset)

        case .clearSelection:
            writeSelection([])
        }
    }

    // MARK: - Private Logic

    /// Single chokepoint for selection mutations — writes both to observable
    /// state (for SwiftUI re-render) and to the persistence cache (for
    /// survival across SwiftUI churn). Every path that mutates
    /// `selectedAssets` must go through here.
    private func writeSelection(_ assets: [GridAsset]) {
        assetGridState.selectedAssets = assets
        AssetGridSelectionCache.update(assets, for: selectionLimit)
    }

    /// Standalone-consumer bootstrap: load the album list then pull assets
    /// from the first one. Picker flow does not use this path — it manages
    /// `currentAlbum` externally and triggers `.selectAlbum` directly.
    private func loadInitialAlbum() async {
        assetGridState.isLoading = true
        await photoKitService.loadAlbumsIfNeeded()
        if let first = photoKitService.albums.first {
            lastLoadedAlbum = first
            await loadAssets(for: first)
        }
        assetGridState.isLoading = false
    }

    private func loadAssets(for album: PhotoLibraryService.AlbumInfo) async {
        PickerPerfLog.event("grid.loadAssets → enter (album=\(album.title))")
        assetGridState.isLoading = true

        // PHASE 1 — bounded top-`gridInitialPageSize` fetch using PhotoKit's
        // partial-sort fast path. This is the ONLY thing the user waits on
        // for first paint. A bounded fetch is dramatically faster than the
        // unbounded sort on large libraries because PhotoKit uses a top-K
        // algorithm and never has to establish ordering for the rest of the
        // album. We also keep this batch small (~one viewport) so the cells
        // mounted on initial paint don't pile dozens of requestImage calls
        // onto PhotoKit's serial queue at once.
        let firstPage = await photoKitService.fetchAssets(in: album, limit: PhotoKitService.gridInitialPageSize)
        if Task.isCancelled {
            PickerPerfLog.event("grid.loadAssets → cancelled after PHASE 1 fetch")
            assetGridState.isLoading = false
            return
        }
        PickerPerfLog.event("grid.loadAssets → PHASE 1 fetched (\(firstPage.count))")

        // Skip assignment if the identifier set hasn't actually changed —
        // prevents SwiftUI from destroying and recreating every cell.
        let newIDs = firstPage.map(\.localIdentifier)
        let oldIDs = assetGridState.assets.compactMap { $0.phAsset?.localIdentifier }
        if newIDs != oldIDs {
            // Invalidate stale pagination state from the previous album so
            // `loadNextPageCore` lazy-spawns a fresh PHASE 2 for THIS album
            // instead of materializing rows from the previous album's
            // PHFetchResult. Without this, scrolling in Selfies after
            // switching from Recents would append Recents photos (because
            // `fetchResult` still pointed at the Recents PHFetchResult set
            // on the prior album's scroll-triggered PHASE 2).
            pendingFullFetch?.cancel()
            pendingFullFetch = nil
            fetchResult = nil

            // Tell PhotoKit to start preparing the cells' thumbnails NOW so
            // requestImage calls hit the warm pool. Order matters: this
            // happens BEFORE the prewarm loop so PhotoKit can serve the
            // prewarm requests from a warmed state.
            photoKitService.setCachedAssets(firstPage, targetSize: PhotoKitService.gridThumbnailTargetSize)
            PickerPerfLog.event("grid.loadAssets → setCachedAssets done (warm started)")

            // Prewarm the visible viewport's thumbnails into ThumbnailCache
            // BEFORE replacing assetGridState.assets, so the new album
            // reveals with a fully-painted viewport instead of empty
            // squares trickling in. The old album stays visible during
            // this ~1.3s window — the trade-off is "longer transition,
            // clean reveal" vs "fast transition, visible trickle." Same
            // total wall-clock either way; different perception. See
            // MEDIA_PICKER_GUIDELINES.md for the rationale.
            let primeCount = min(PhotoKitService.gridInitialPrewarmCount, firstPage.count)
            PickerPerfLog.event("grid.loadAssets → prewarm start (\(primeCount) cells)")
            await photoKitService.prewarmGridCells(firstPage.prefix(primeCount))
            if Task.isCancelled {
                PickerPerfLog.event("grid.loadAssets → cancelled after prewarm")
                assetGridState.isLoading = false
                return
            }
            PickerPerfLog.event("grid.loadAssets → prewarm done")

            // NOW swap the visible content. Cells mount with cache hits
            // for the prewarmed viewport.
            assetGridState.assets = firstPage.map { .phAsset($0) }
        }
        assetGridState.isLoading = false
        // ↑ User sees the first ~20 cells from here. NO PHASE 2 — it's
        //   deferred to the first sentinel hit in `loadNextPageCore`. This
        //   leaves PhotoKit's serial queue free for the library previewer
        //   and gallery shortcut to load without contention.
    }

    // MARK: - Pagination (load next page)

    /// Sync fire-and-forget entry point called by `AssetGridView` when the
    /// sentinel cell appears. Spawns a tracked Task so a mid-scroll dismiss
    /// cancels in-flight materialization. See `loadNextPageCore` for the
    /// actual work.
    public func loadNextPageIfNeeded() {
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadNextPageCore()
        }
        tasks.append(task)
    }

    private func loadNextPageCore() async {
        guard !isLoadingPage else { return }                 // re-entry guard
        guard let album = lastLoadedAlbum else { return }    // no album, no pagination

        // Lazy PHASE 2 — kick off the unbounded fetch HERE on the first
        // sentinel hit, not eagerly in `loadAssets`. This keeps PhotoKit's
        // serial queue free during sheet-open so the library previewer and
        // gallery shortcut aren't competing with the ~500-1000ms unbounded
        // sort. PhotoKit only does bulk work after the user has shown
        // intent to scroll past page 1.
        if fetchResult == nil {
            if pendingFullFetch == nil {
                PickerPerfLog.event("grid.loadNextPage → triggering lazy PHASE 2")
                let task = Task { [weak self] in
                    guard let self else { return }
                    PickerPerfLog.event("grid.loadNextPage → PHASE 2 start (lazy)")
                    let fullResult = await self.photoKitService.fetchAssetsResult(in: album)
                    self.fetchResult = fullResult
                    PickerPerfLog.event("grid.loadNextPage → PHASE 2 ready (total=\(fullResult.count))")
                }
                pendingFullFetch = task
                tasks.append(task)
            }
            if let pending = pendingFullFetch {
                PickerPerfLog.event("grid.loadNextPage → waiting on PHASE 2")
                await pending.value
            }
        }

        guard let result = fetchResult else { return }
        let currentCount = assetGridState.assets.count
        guard currentCount < result.count else { return }    // end of library

        isLoadingPage = true
        defer { isLoadingPage = false }

        let nextRange = currentCount..<min(currentCount + Self.paginationPageSize, result.count)
        PickerPerfLog.event("grid.loadNextPage → start (range=\(nextRange.lowerBound)..<\(nextRange.upperBound))")

        let nextPage = await photoKitService.materialize(from: result, range: nextRange)
        PickerPerfLog.event("grid.loadNextPage → materialized (\(nextPage.count))")

        // Append to the grid. SwiftUI's LazyVGrid only lays out the cells
        // that just came on-screen — no re-layout of existing cells.
        assetGridState.assets.append(contentsOf: nextPage.map { .phAsset($0) })

        // Extend the PHCachingImageManager warm pool to cover the new
        // assets too. setCachedAssets is no-op-safe when the asset set
        // hasn't changed; here it'll stop caching the old N and start
        // caching the new N + page assets.
        let allMaterialized = assetGridState.assets.compactMap { $0.phAsset }
        photoKitService.setCachedAssets(allMaterialized, targetSize: PhotoKitService.gridThumbnailTargetSize)

        PickerPerfLog.event("grid.loadNextPage → appended (now=\(assetGridState.assets.count) total=\(result.count))")
    }

    private func toggleAssetSelection(_ asset: GridAsset) {
        var newSelection = assetGridState.selectedAssets
        if let index = newSelection.firstIndex(of: asset) {
            newSelection.remove(at: index)
        } else if newSelection.count < selectionLimit {
            newSelection.append(asset)
        }
        writeSelection(newSelection)
    }

    public func isSelected(_ asset: GridAsset) -> Bool {
        assetGridState.selectedAssets.contains(asset)
    }

    public func selectionIndex(for asset: GridAsset) -> Int? {
        if let index = assetGridState.selectedAssets.firstIndex(of: asset) {
            return index + 1 // 1-based index for badge
        }
        return nil
    }

    // MARK: - Thumbnails (called by AssetGridView per cell)

    /// Synchronous thumbnail lookup. The grid passes the result to each cell
    /// as `initialImage` so the cell paints on its first frame without an
    /// async hop. Returns nil on miss; the cell's `.task(id:)` then calls
    /// `requestThumbnail` to populate.
    ///
    /// PHAsset path: peeks the process-wide `ThumbnailCache` via the service.
    /// MediaItem path: returns the bundled bitmap directly (no async needed).
    public func thumbnail(for asset: GridAsset) -> UIImage? {
        switch asset {
        case .phAsset(let ph):
            return photoKitService.cachedThumbnail(for: ph)
        case .mediaItem(let item):
            return item.thumbnail
        }
    }

    /// Async thumbnail fetch for a single grid asset. The grid passes this
    /// to each cell as `loadAsync`; the cell awaits it in `.task(id:)`,
    /// which auto-cancels if the cell disappears before the load resolves.
    /// MediaItem cells return nil immediately (they already carry their
    /// bitmap; the cell uses `initialImage` instead).
    public func requestThumbnail(for asset: GridAsset) async -> UIImage? {
        guard case .phAsset(let ph) = asset else { return nil }
        return await withCheckedContinuation { continuation in
            photoKitService.loadThumbnail(for: ph, size: PhotoKitService.gridThumbnailTargetSize) { image in
                continuation.resume(returning: image)
            }
        }
    }

    /// Lightweight refresh of the current album's assets. Called from the
    /// PhotoKit change observer. Uses `lastLoadedAlbum` (the album we most
    /// recently loaded) — never touches `assetGridState.isLoading` or any other
    /// state that would cascade an `@Observable` re-eval through the grid.
    private func refreshCurrentAssets() async {
        guard let album = lastLoadedAlbum else { return }

        let result = await photoKitService.fetchAssetsResult(in: album)

        // Defensive: never shrink a populated grid to empty here.
        // Immediately after iOS dismisses the Limited Access popup ("Keep
        // Current Selection"), PhotoKit's selection set is briefly empty
        // during the dismiss transition. A naive replace would clear the
        // grid to [] and then refill it a moment later — visible as a
        // full-grid black flash. If the next fetch reports empty while we
        // hold a populated state, treat it as transient and wait for the
        // follow-up notification with the real set.
        if result.count == 0 && !assetGridState.assets.isEmpty { return }

        // Re-materialize at LEAST as many cells as currently displayed so
        // the user doesn't lose scroll position. If the library shrunk
        // (e.g., user deleted photos), clamp to the new total.
        let currentCount = assetGridState.assets.count
        let refreshCount = min(max(currentCount, Self.paginationPageSize), result.count)
        let materialized = await photoKitService.materialize(
            from: result,
            range: 0..<refreshCount
        )

        let newIDs = materialized.map(\.localIdentifier)
        let oldIDs = assetGridState.assets.compactMap { $0.phAsset?.localIdentifier }
        guard newIDs != oldIDs else { return }

        self.fetchResult = result
        assetGridState.assets = materialized.map { .phAsset($0) }
        photoKitService.setCachedAssets(materialized, targetSize: PhotoKitService.gridThumbnailTargetSize)
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension AssetGridViewModel: PHPhotoLibraryChangeObserver {
    /// Sync nonisolated callback per Apple's protocol. Must be marked
    /// `nonisolated` to satisfy the protocol conformance since the class
    /// itself is `@MainActor`. Hops to MainActor via a Task to do the
    /// async refresh work.
    public nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            await self.refreshCurrentAssets()
        }
    }
}
