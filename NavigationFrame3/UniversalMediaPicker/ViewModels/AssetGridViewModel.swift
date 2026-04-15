import SwiftUI
import Photos
import Observation

// MARK: - Actions
public enum AssetGridAction {
    case loadInitialData
    case selectAlbum(PhotoAlbumService.AlbumInfo)
    case selectAsset(PHAsset)
    case toggleMultiSelect
    case toggleAssetSelection(PHAsset)
    case clearSelection
}

// MARK: - State Lens
public struct AssetGridState {
    public var albums: [PhotoAlbumService.AlbumInfo] = []
    public var currentAlbum: PhotoAlbumService.AlbumInfo?
    public var assets: [PHAsset] = []
    public var selectedAssets: [PHAsset] = [] // Ordered for numbered badges
    public var isMultiSelectActive: Bool = false
    public var isLoading: Bool = false
    public var errorMessage: String?
}

// MARK: - ViewModel
@Observable
public final class AssetGridViewModel {
    private let albumService = PhotoAlbumService.shared
    private let selectionLimit: Int
    
    // The Lens
    public var state = AssetGridState()
    
    public init(selectionLimit: Int = 1) {
        self.selectionLimit = selectionLimit
    }
    
    // The Trigger
    public func trigger(_ action: AssetGridAction) {
        switch action {
        case .loadInitialData:
            loadAlbums()
            
        case .selectAlbum(let album):
            state.currentAlbum = album
            loadAssets(for: album)
            
        case .selectAsset(let asset):
            if state.isMultiSelectActive {
                toggleAssetSelection(asset)
            } else {
                state.selectedAssets = [asset]
            }
            
        case .toggleMultiSelect:
            state.isMultiSelectActive.toggle()
            if !state.isMultiSelectActive {
                state.selectedAssets = []
            }
            
        case .toggleAssetSelection(let asset):
            toggleAssetSelection(asset)
            
        case .clearSelection:
            state.selectedAssets = []
        }
    }
    
    // MARK: - Private Logic
    
    private func loadAlbums() {
        state.isLoading = true
        let albums = albumService.fetchAlbums()
        state.albums = albums
        
        if let first = albums.first {
            state.currentAlbum = first
            loadAssets(for: first)
        }
        state.isLoading = false
    }
    
    private func loadAssets(for album: PhotoAlbumService.AlbumInfo) {
        state.isLoading = true
        state.assets = albumService.fetchAssets(in: album.collection)
        state.isLoading = false
    }
    
    private func toggleAssetSelection(_ asset: PHAsset) {
        if let index = state.selectedAssets.firstIndex(of: asset) {
            state.selectedAssets.remove(at: index)
        } else {
            if state.selectedAssets.count < selectionLimit {
                state.selectedAssets.append(asset)
            }
        }
    }
    
    public func isSelected(_ asset: PHAsset) -> Bool {
        state.selectedAssets.contains(asset)
    }
    
    public func selectionIndex(for asset: PHAsset) -> Int? {
        state.selectedAssets.firstIndex(of: asset).map { $0 + 1 }
    }
}
