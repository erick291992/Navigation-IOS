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
@Observable
public final class AssetGridViewModel: NSObject {
    private let photoKit = PhotoKitService.shared
    public let selectionLimit: Int

    public var state = AssetGridState()

    /// Internal cache of the album most recently passed to `.selectAlbum` /
    /// `.loadInitialData`. Used only by the PhotoKit change observer's
    /// refresh path so it knows which album to re-fetch. Not exposed; not
    /// `@Observable`; views never see it.
    @ObservationIgnored private var lastLoadedAlbum: PhotoLibraryService.AlbumInfo?

    // MARK: - Shared instance cache
    //
    // The FlickerDx logs proved that the picker's `@State viewModel` is being
    // torn down and re-initialized 4–5x per session — driven by upstream
    // identity churn (the AnyView wrapping inside `SheetNavigationContainer.body`
    // recreates the sheet content tree on every NavigationCoordinator body
    // re-eval). Each fresh `PickerViewModel` used to construct a fresh
    // `AssetGridViewModel`, which started with `state.assets == []` and only
    // refilled after `loadInitialData` won the async race. *That race* is the
    // visible "grid goes black, all cells flash at once" on Limited-Access
    // popup dismiss.
    //
    // The fix: cache the grid VM by `selectionLimit`. Identity churn upstream
    // no longer matters — every fresh `PickerViewModel.init` resolves to the
    // *same* AssetGridViewModel, with its loaded assets intact. The user-facing
    // selection set is cleared per session via `prepareForNewSession()`
    // (called from `MediaPickerModifier`'s sheet onDismiss).
    @MainActor private static var cache: [Int: AssetGridViewModel] = [:]

    @MainActor public static func shared(selectionLimit: Int) -> AssetGridViewModel {
        if let cached = cache[selectionLimit] { return cached }
        let fresh = AssetGridViewModel(selectionLimit: selectionLimit)
        cache[selectionLimit] = fresh
        return fresh
    }

    /// Resets the per-session UI state (selection, multi-select flag, error)
    /// without throwing away the loaded asset list. Call this when a picker
    /// sheet is dismissed so the next open starts clean.
    @MainActor public func prepareForNewSession() {
        state.selectedAssets = []
        state.isMultiSelectActive = false
        state.errorMessage = nil
    }

    public init(selectionLimit: Int = 1) {
        self.selectionLimit = selectionLimit
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
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
                state.selectedAssets = [asset]
            }

        case .toggleMultiSelect:
            break

        case .toggleAssetSelection(let asset):
            toggleAssetSelection(asset)

        case .clearSelection:
            state.selectedAssets = []
        }
    }

    // MARK: - Private Logic

    /// Standalone-consumer bootstrap: load the album list then pull assets
    /// from the first one. Picker flow does not use this path — it manages
    /// `currentAlbum` externally and triggers `.selectAlbum` directly.
    private func loadInitialAlbum() async {
        state.isLoading = true
        await photoKit.loadAlbumsIfNeeded()
        if let first = photoKit.albums.first {
            lastLoadedAlbum = first
            await loadAssets(for: first)
        }
        state.isLoading = false
    }

    private func loadAssets(for album: PhotoLibraryService.AlbumInfo) async {
        state.isLoading = true

        let phAssets = await photoKit.fetchAssets(in: album)

        // Skip assignment if the identifier set hasn't actually changed —
        // prevents SwiftUI from destroying and recreating every cell.
        let newIDs = phAssets.map(\.localIdentifier)
        let oldIDs = state.assets.compactMap { $0.phAsset?.localIdentifier }
        if newIDs != oldIDs {
            state.assets = phAssets.map { .phAsset($0) }
        }
        state.isLoading = false
    }

    private func toggleAssetSelection(_ asset: GridAsset) {
        if let index = state.selectedAssets.firstIndex(of: asset) {
            state.selectedAssets.remove(at: index)
        } else {
            if state.selectedAssets.count < selectionLimit {
                state.selectedAssets.append(asset)
            }
        }
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

    /// Lightweight refresh of the current album's assets. Called from the
    /// PhotoKit change observer. Uses `lastLoadedAlbum` (the album we most
    /// recently loaded) — never touches `state.isLoading` or any other
    /// state that would cascade an `@Observable` re-eval through the grid.
    private func refreshCurrentAssets() async {
        guard let album = lastLoadedAlbum else { return }

        let phAssets = await photoKit.fetchAssets(in: album)

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
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension AssetGridViewModel: PHPhotoLibraryChangeObserver {
    /// Sync nonisolated callback per Apple's protocol. Hops to MainActor via
    /// a Task to do the async refresh work.
    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            await self.refreshCurrentAssets()
        }
    }
}
