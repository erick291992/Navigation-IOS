import SwiftUI
import Photos
import Observation

// MARK: - Actions
public enum AssetGridAction {
    case loadInitialData
    case loadHistory([MediaItem])
    case selectAlbum(PhotoLibraryService.AlbumInfo)
    case selectAsset(GridAsset)
    case toggleMultiSelect
    case toggleAssetSelection(GridAsset)
    case clearSelection
}

// MARK: - State Lens
//
// `currentAlbum` and `albums` are NOT stored here in the rebuild. They're
// owned by `PickerViewModel` (the picker-level coordinator) and flow into
// `AssetGridView` via `@Binding` — Apple's `Picker(selection:)` pattern.
// The grid VM itself is concerned only with the assets it's been told to
// load and the user's selection state.
public struct AssetGridState {
    public var assets: [GridAsset] = []
    public var selectedAssets: [GridAsset] = [] // Ordered for numbered badges
    public var isMultiSelectActive: Bool = false
    public var isLoading: Bool = false
    public var errorMessage: String?
}

// MARK: - ViewModel
//
// `@MainActor` at the class level — matches the rebuild's other view models
// (PickerViewModel, CameraViewfinderViewModel, LibraryViewfinderViewModel).
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
// time via plain `@State`. The grid's loaded `state.assets` is also not
// cached (PhotoKit re-fetches are fast; skeleton UI bridges the brief
// reload). See `AssetGridSelectionCache.swift` for the full rationale.
@MainActor
@Observable
public final class AssetGridViewModel: NSObject {
    private let photoKitService: PhotoKitService
    public let selectionLimit: Int

    public var state = AssetGridState()

    /// Internal cache of the album most recently passed to `.selectAlbum` /
    /// `.loadInitialData`. Used only by the PhotoKit change observer's
    /// refresh path so it knows which album to re-fetch. Not exposed; not
    /// `@Observable`; views never see it.
    @ObservationIgnored private var lastLoadedAlbum: PhotoLibraryService.AlbumInfo?

    // MARK: - Pagination state
    //
    // The grid uses a **two-phase hybrid fetch** model:
    //
    // PHASE 1 (on the critical path) — `fetchAssets(in:, limit: pageSize)`
    //   returns the first page eagerly. This call uses PhotoKit's top-K
    //   fast path (because of the `fetchLimit`), which is dramatically
    //   faster than an unbounded fetch on large libraries because PhotoKit
    //   doesn't have to establish the full sort order over the entire
    //   library — it only needs to find the top N most recent.
    //
    // PHASE 2 (off the critical path) — a background `Task` does the
    //   unbounded `fetchAssetsResult` and stores the lazy `PHFetchResult`
    //   in `fetchResult`. This is what pagination needs to materialize
    //   pages 60+ on scroll. The unbounded sort PhotoKit does here is
    //   expensive (~500-1000ms on a 33k-photo library), but it runs AFTER
    //   the user is already looking at the grid — they don't wait on it.
    //
    // If the user scrolls fast enough to hit the pagination sentinel
    // before PHASE 2 finishes, `loadNextPageCore` awaits `pendingFullFetch`
    // instead of no-op'ing. So no "stuck at 60" wall for fast scrollers;
    // they just briefly wait for PHASE 2 to complete.
    //
    // See CODING_GUIDELINES.md §3 "Bounded fast-path + background unbounded"
    // for the general pattern.

    @ObservationIgnored private var fetchResult: PHFetchResult<PHAsset>?
    @ObservationIgnored private var isLoadingPage = false   // re-entry guard for loadNextPage

    /// PHASE 2 background fetch handle. `loadNextPageCore` awaits this if
    /// the user scrolls past the first page before the unbounded fetch
    /// completes. Cancelled via the `tasks` array on deinit.
    @ObservationIgnored private var pendingFullFetch: Task<Void, Never>?

    /// Cells per page. 60 covers ~3-4 screens at a 4-column grid — enough
    /// that scrolling doesn't immediately trigger another fetch, small
    /// enough that initial paint isn't blocked materializing 200+ assets.
    private static let pageSize = 60

    /// How many cells before the end of the materialized list to start
    /// loading the next page. 10 cells ≈ 2.5 rows of buffer — gives PhotoKit
    /// time to materialize before the user actually scrolls past the end.
    private static let sentinelBuffer = 10

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
        state.selectedAssets = AssetGridSelectionCache.selection(for: selectionLimit)
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
        let count = state.assets.count
        guard count > 0 else { return nil }
        let sentinelIndex = max(0, count - Self.sentinelBuffer)
        return state.assets[sentinelIndex].id
    }

    // MARK: - Session lifecycle

    /// Resets the per-session UI state (selection, multi-select flag, error)
    /// without throwing away the loaded asset list. Call this when a picker
    /// sheet is dismissed so the next open starts clean.
    public func prepareForNewSession() {
        writeSelection([])
        state.isMultiSelectActive = false
        state.errorMessage = nil
    }

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
            state.assets = [] // Clear instantly to prevent "Ghost Library" flashes
            Task {
                let assets = items.map { GridAsset.mediaItem($0) }
                state.assets = assets
            }

        case .selectAlbum(let album):
            lastLoadedAlbum = album
            Task { await loadAssets(for: album) }

        case .selectAsset(let asset):
            if selectionLimit > 1 {
                toggleAssetSelection(asset)
            } else {
                writeSelection([asset])
            }

        case .toggleMultiSelect:
            break

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
        state.selectedAssets = assets
        AssetGridSelectionCache.update(assets, for: selectionLimit)
    }

    /// Standalone-consumer bootstrap: load the album list then pull assets
    /// from the first one. Picker flow does not use this path — it manages
    /// `currentAlbum` externally and triggers `.selectAlbum` directly.
    private func loadInitialAlbum() async {
        state.isLoading = true
        await photoKitService.loadAlbumsIfNeeded()
        if let first = photoKitService.albums.first {
            lastLoadedAlbum = first
            await loadAssets(for: first)
        }
        state.isLoading = false
    }

    private func loadAssets(for album: PhotoLibraryService.AlbumInfo) async {
        PickerPerfLog.event("grid.loadAssets → enter (album=\(album.title))")
        state.isLoading = true

        // PHASE 1 — bounded top-`pageSize` fetch using PhotoKit's partial-sort
        // fast path. This is the ONLY thing the user actually waits on for
        // first paint. A bounded fetch is dramatically faster than the
        // unbounded sort on large libraries because PhotoKit uses a top-K
        // algorithm and never has to establish ordering for the rest of
        // the album.
        let firstPage = await photoKitService.fetchAssets(in: album, limit: Self.pageSize)
        PickerPerfLog.event("grid.loadAssets → PHASE 1 fetched (\(firstPage.count))")

        // Skip assignment if the identifier set hasn't actually changed —
        // prevents SwiftUI from destroying and recreating every cell.
        let newIDs = firstPage.map(\.localIdentifier)
        let oldIDs = state.assets.compactMap { $0.phAsset?.localIdentifier }
        if newIDs != oldIDs {
            state.assets = firstPage.map { .phAsset($0) }
            // Tell PhotoKit to start preparing the cells' thumbnails NOW,
            // before SwiftUI lays them out — first paint reads from the
            // warm pool instead of paying the disk/decode/resize cost.
            photoKitService.setCachedAssets(firstPage, targetSize: PhotoKitService.gridThumbnailTargetSize)
            PickerPerfLog.event("grid.loadAssets → setCachedAssets done (warm started)")
        }
        state.isLoading = false
        // ↑ User sees the first 60 cells from this point on. PHASE 2 below is
        //   off the critical path — runs after first paint, doesn't block.

        // PHASE 2 — background fetch of the unbounded `PHFetchResult`. This
        // is what pagination needs to materialize pages 60+ on scroll. The
        // unbounded sort PhotoKit does here is exactly the same work the
        // pre-hybrid code did — we just moved it OFF the critical path so
        // it no longer blocks first paint. Stored on `pendingFullFetch` so
        // `loadNextPageCore` can await it if the user scrolls fast.
        let task = Task { [weak self] in
            guard let self else { return }
            PickerPerfLog.event("grid.loadAssets → PHASE 2 start (background)")
            let fullResult = await self.photoKitService.fetchAssetsResult(in: album)
            self.fetchResult = fullResult
            PickerPerfLog.event("grid.loadAssets → PHASE 2 ready (total=\(fullResult.count))")
        }
        self.pendingFullFetch = task
        tasks.append(task)
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

        // Wait for PHASE 2 background fetch if the user scrolled past the
        // first page before it completed. Without this, fast-scrolling
        // users would hit a "wall" at cell 60 with no auto-retry once
        // PHASE 2 eventually finishes. Awaiting the task gives PHASE 2 a
        // chance to populate `fetchResult` before we check it.
        if fetchResult == nil, let pending = pendingFullFetch {
            PickerPerfLog.event("grid.loadNextPage → waiting on PHASE 2")
            await pending.value
        }

        guard let result = fetchResult else { return }
        let currentCount = state.assets.count
        guard currentCount < result.count else { return }    // end of library

        isLoadingPage = true
        defer { isLoadingPage = false }

        let nextRange = currentCount..<min(currentCount + Self.pageSize, result.count)
        PickerPerfLog.event("grid.loadNextPage → start (range=\(nextRange.lowerBound)..<\(nextRange.upperBound))")

        let nextPage = await photoKitService.materialize(from: result, range: nextRange)
        PickerPerfLog.event("grid.loadNextPage → materialized (\(nextPage.count))")

        // Append to the grid. SwiftUI's LazyVGrid only lays out the cells
        // that just came on-screen — no re-layout of existing cells.
        state.assets.append(contentsOf: nextPage.map { .phAsset($0) })

        // Extend the PHCachingImageManager warm pool to cover the new
        // assets too. setCachedAssets is no-op-safe when the asset set
        // hasn't changed; here it'll stop caching the old N and start
        // caching the new N + page assets.
        let allMaterialized = state.assets.compactMap { $0.phAsset }
        photoKitService.setCachedAssets(allMaterialized, targetSize: PhotoKitService.gridThumbnailTargetSize)

        PickerPerfLog.event("grid.loadNextPage → appended (now=\(state.assets.count) total=\(result.count))")
    }

    private func toggleAssetSelection(_ asset: GridAsset) {
        var newSelection = state.selectedAssets
        if let index = newSelection.firstIndex(of: asset) {
            newSelection.remove(at: index)
        } else if newSelection.count < selectionLimit {
            newSelection.append(asset)
        }
        writeSelection(newSelection)
    }

    public func isSelected(_ asset: GridAsset) -> Bool {
        state.selectedAssets.contains(asset)
    }

    public func selectionIndex(for asset: GridAsset) -> Int? {
        if let index = state.selectedAssets.firstIndex(of: asset) {
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
    /// recently loaded) — never touches `state.isLoading` or any other
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
        if result.count == 0 && !state.assets.isEmpty { return }

        // Re-materialize at LEAST as many cells as currently displayed so
        // the user doesn't lose scroll position. If the library shrunk
        // (e.g., user deleted photos), clamp to the new total.
        let currentCount = state.assets.count
        let refreshCount = min(max(currentCount, Self.pageSize), result.count)
        let materialized = await photoKitService.materialize(
            from: result,
            range: 0..<refreshCount
        )

        let newIDs = materialized.map(\.localIdentifier)
        let oldIDs = state.assets.compactMap { $0.phAsset?.localIdentifier }
        guard newIDs != oldIDs else { return }

        self.fetchResult = result
        state.assets = materialized.map { .phAsset($0) }
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
