import SwiftUI
import Photos
import Observation

// MARK: - Actions
public enum AssetGridAction {
    case loadInitialData
    case loadHistory([MediaItem])
    case selectAlbum(PhotoAlbumService.AlbumInfo)
    case selectAsset(GridAsset)
    case toggleMultiSelect
    case toggleAssetSelection(GridAsset)
    case clearSelection
}

// MARK: - State Lens
public struct AssetGridState {
    public var albums: [PhotoAlbumService.AlbumInfo] = []
    public var currentAlbum: PhotoAlbumService.AlbumInfo?
    public var assets: [GridAsset] = []
    public var selectedAssets: [GridAsset] = [] // Ordered for numbered badges
    public var isMultiSelectActive: Bool = false
    public var isLoading: Bool = false
    public var errorMessage: String?
}

// MARK: - ViewModel
@Observable
public final class AssetGridViewModel: NSObject, PHPhotoLibraryChangeObserver {
    private let albumService = PhotoAlbumService.shared
    public let selectionLimit: Int

    // The Lens
    public var state = AssetGridState()

    // MARK: - Shared instance cache
    //
    // The FlickerDx logs proved that `UnifiedCreatorView`'s `@State viewModel`
    // is being torn down and re-initialized 4–5x per picker session — driven
    // by upstream identity churn (the AnyView wrapping inside
    // `SheetNavigationContainer.body` recreates the sheet content tree on
    // every NavigationCoordinator body re-eval). Each fresh `UnifiedCreatorViewModel`
    // used to construct a fresh `AssetGridViewModel`, which started with
    // `state.assets == []` and only refilled after `loadInitialData` won the
    // async race. *That race* is the visible "grid goes black, all cells flash
    // at once" on Limited-Access popup dismiss.
    //
    // The fix: cache the grid VM by `selectionLimit`. Identity churn upstream
    // no longer matters — every fresh `UnifiedCreatorViewModel.init` resolves
    // to the *same* AssetGridViewModel, with its loaded assets and album state
    // intact. The user-facing selection set is cleared per session via
    // `prepareForNewSession()` (called from `MediaPickerModifier`'s sheet
    // onDismiss), so the cache doesn't leak the previous picker's selection
    // into the next one.
    @MainActor private static var cache: [Int: AssetGridViewModel] = [:]

    @MainActor public static func shared(selectionLimit: Int) -> AssetGridViewModel {
        if let cached = cache[selectionLimit] { return cached }
        let fresh = AssetGridViewModel(selectionLimit: selectionLimit)
        cache[selectionLimit] = fresh
        return fresh
    }

    /// Resets the per-session UI state (selection, multi-select flag, error)
    /// without throwing away the loaded asset list or album choice. Call this
    /// when a picker sheet is dismissed so the next open starts clean.
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
    
    // The Trigger
    public func trigger(_ action: AssetGridAction) {
        switch action {
        case .loadInitialData:
            Task { await loadAlbums() }
            
        case .loadHistory(let items):
            state.assets = [] // Clear instantly to prevent "Ghost Library" flashes
            state.currentAlbum = nil // Indicates we are in history mode
            Task {
                let assets = await Task.detached(priority: .userInitiated) {
                    items.map { GridAsset.mediaItem($0) }
                }.value
                await MainActor.run {
                    self.state.assets = assets
                }
            }
            
        case .selectAlbum(let album):
            state.currentAlbum = album
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
    
    private func loadAlbums() async {
        state.isLoading = true

        // Principal Move: Yield the main thread to let the UI (pink dot) render first.
        await Task.yield()

        // Move heavy PhotoKit work to background
        let service = self.albumService
        let albums = await Task.detached(priority: .userInitiated) {
            service.fetchAlbums()
        }.value

        state.albums = albums

        if let first = albums.first {
            state.currentAlbum = first
            await loadAssets(for: first)
        }
        state.isLoading = false
    }

    private func loadAssets(for album: PhotoAlbumService.AlbumInfo) async {
        state.isLoading = true

        // Yield again to ensure smooth UI interaction
        await Task.yield()

        // Move heavy PhotoKit work to background
        let service = self.albumService
        let phAssets = await Task.detached(priority: .userInitiated) {
            service.fetchAssets(in: album.collection)
        }.value

        // Skip assignment if the data hasn't actually changed — prevents
        // SwiftUI from destroying and recreating every cell (thumbnail flicker).
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
    
    // MARK: - PHPhotoLibraryChangeObserver

    nonisolated public func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Lightweight refresh: re-fetch the current album's assets ONLY, and only
        // write `state.assets` if the identifier set actually changed. We never
        // touch `state.isLoading`, `state.albums`, or `state.currentAlbum` here —
        // each of those is its own @Observable notification that would cascade a
        // re-eval through the grid and produce the flicker on Limited Access
        // popup dismiss (where the library hasn't actually changed at all).
        Task { @MainActor in
            await self.refreshCurrentAssets()
        }
    }

    private func refreshCurrentAssets() async {
        guard let album = state.currentAlbum else { return }

        let service = self.albumService
        let phAssets = await Task.detached(priority: .userInitiated) {
            service.fetchAssets(in: album.collection)
        }.value

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
