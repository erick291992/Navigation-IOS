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
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
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

        let phAssets = await photoKitService.fetchAssets(in: album)
        PickerPerfLog.event("grid.loadAssets → fetchAssets done (\(phAssets.count))")

        // Skip assignment if the identifier set hasn't actually changed —
        // prevents SwiftUI from destroying and recreating every cell.
        let newIDs = phAssets.map(\.localIdentifier)
        let oldIDs = state.assets.compactMap { $0.phAsset?.localIdentifier }
        if newIDs != oldIDs {
            state.assets = phAssets.map { .phAsset($0) }
            // Tell PhotoKit to start preparing the cells' thumbnails NOW,
            // before SwiftUI lays them out — first paint reads from the
            // warm pool instead of paying the disk/decode/resize cost.
            photoKitService.setCachedAssets(phAssets, targetSize: PhotoKitService.gridThumbnailTargetSize)
            PickerPerfLog.event("grid.loadAssets → setCachedAssets done (warm started)")
        }
        state.isLoading = false
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

        let phAssets = await photoKitService.fetchAssets(in: album)

        // Defensive: never shrink a populated grid to empty here.
        // Immediately after iOS dismisses the Limited Access popup ("Keep
        // Current Selection"), PhotoKit's selection set is briefly empty
        // during the dismiss transition. A naive replace would clear the
        // grid to [] and then refill it a moment later — visible as a
        // full-grid black flash. If the next fetch reports empty while we
        // hold a populated state, treat it as transient and wait for the
        // follow-up notification with the real set.
        if phAssets.isEmpty && !state.assets.isEmpty { return }

        let newIDs = phAssets.map(\.localIdentifier)
        let oldIDs = state.assets.compactMap { $0.phAsset?.localIdentifier }
        guard newIDs != oldIDs else { return }

        state.assets = phAssets.map { .phAsset($0) }
        photoKitService.setCachedAssets(phAssets, targetSize: PhotoKitService.gridThumbnailTargetSize)
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
