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
        // Trigger a reload when the library changes, but ONLY if we are currently
        // showing library assets (i.e. currentAlbum is not nil).
        // If currentAlbum is nil, we are likely in history/reuse mode and should not overwrite.
        Task { @MainActor in
            if self.state.currentAlbum != nil {
                self.trigger(.loadInitialData)
            }
        }
    }
}
