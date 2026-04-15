import Foundation
import Photos
import UIKit

/// A stateless service to fetch PhotoKit album metadata and assets.
/// Designed for the custom AssetGridView.
public final class PhotoAlbumService {
    public static let shared = PhotoAlbumService()
    private init() {}

    public struct AlbumInfo: Identifiable, Hashable {
        public let id: String
        public let title: String
        public let count: Int
        public let icon: String
        public let collection: PHAssetCollection
        
        public static func == (lhs: AlbumInfo, rhs: AlbumInfo) -> Bool {
            lhs.id == rhs.id
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    /// Discovers smart albums and user-created albums.
    public func fetchAlbums() -> [AlbumInfo] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return []
        }
        
        var albums: [AlbumInfo] = []
        
        // 1. Smart Albums (Recents, Favorites, Videos, etc.)
        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smartAlbums.enumerateObjects { collection, _, _ in
            if let info = self.makeAlbumInfo(from: collection) {
                // Prioritize certain albums by placing them at the front
                if collection.assetCollectionSubtype == .smartAlbumUserLibrary {
                    albums.insert(info, at: 0) // Recents at the top
                } else if info.count > 0 {
                    albums.append(info)
                }
            }
        }
        
        // 2. User Albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            if let info = self.makeAlbumInfo(from: collection), info.count > 0 {
                albums.append(info)
            }
        }
        
        return albums
    }

    /// Fetches assets for a specific album.
    public func fetchAssets(in collection: PHAssetCollection, limit: Int = 200) -> [PHAsset] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return []
        }
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        
        let fetchResult = PHAsset.fetchAssets(in: collection, options: options)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    private func makeAlbumInfo(from collection: PHAssetCollection) -> AlbumInfo? {
        let options = PHFetchOptions()
        let fetchResult = PHAsset.fetchAssets(in: collection, options: options)
        
        let icon: String
        switch collection.assetCollectionSubtype {
        case .smartAlbumUserLibrary: icon = "photo.on.rectangle"
        case .smartAlbumFavorites: icon = "heart.fill"
        case .smartAlbumVideos: icon = "video.fill"
        case .smartAlbumPanoramas: icon = "mountain.2.fill"
        case .smartAlbumBursts: icon = "stack.fill"
        case .smartAlbumScreenshots: icon = "iphone"
        default: icon = "folder.fill"
        }
        
        return AlbumInfo(
            id: collection.localIdentifier,
            title: collection.localizedTitle ?? "Unknown",
            count: fetchResult.count,
            icon: icon,
            collection: collection
        )
    }
}
