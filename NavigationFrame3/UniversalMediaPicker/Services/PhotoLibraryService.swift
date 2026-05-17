import Foundation
import Photos

/// Mini-repository for raw PhotoKit data operations.
///
/// Plain class — no isolation, no observable state. All methods are `async`;
/// awaiting them from any context hops execution to the cooperative thread pool
/// per SE-0338, so the heavy PhotoKit calls (`PHAsset.fetchAssets`,
/// `PHAssetCollection.fetchAssetCollections`) run off the main thread
/// automatically — no `Task.detached` ceremony, no `@MainActor` annotations.
///
/// Consumed by `PhotoKitService` (the `@Observable` facade); view models do not
/// reach this type directly. The facade gates authorization and decides when to
/// invoke these methods; the repository trusts the caller and just executes.
public final class PhotoLibraryService {
    public static let shared = PhotoLibraryService()
    private init() {}

    /// Album metadata + the underlying `PHAssetCollection` reference.
    /// Owned by the repository because it wraps Apple's framework type.
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

    // MARK: - Authorization

    /// Bridges `PHPhotoLibrary.requestAuthorization` (callback-based) into
    /// structured async via `withCheckedContinuation`.
    public func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                continuation.resume(returning: newStatus)
            }
        }
    }

    // MARK: - Recent assets (used by the viewfinder + gallery shortcut)

    /// Fetch the most recent N image assets, newest first.
    /// Callers are expected to gate on authorization before invoking.
    public func fetchRecentAssets(limit: Int) async -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit

        let result = PHAsset.fetchAssets(with: .image, options: options)

        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    // MARK: - Albums (used by the asset grid)

    /// Discovers smart albums (Recents, Favorites, Videos, etc.) and
    /// user-created albums. Recents is always placed first; other albums
    /// are included only if they contain at least one asset.
    public func fetchAlbums() async -> [AlbumInfo] {
        var albums: [AlbumInfo] = []

        // 1. Smart Albums.
        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .any, options: nil
        )
        smartAlbums.enumerateObjects { collection, _, _ in
            if let info = self.makeAlbumInfo(from: collection) {
                if collection.assetCollectionSubtype == .smartAlbumUserLibrary {
                    albums.insert(info, at: 0) // Recents at the top.
                } else if info.count > 0 {
                    albums.append(info)
                }
            }
        }

        // 2. User Albums.
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: nil
        )
        userAlbums.enumerateObjects { collection, _, _ in
            if let info = self.makeAlbumInfo(from: collection), info.count > 0 {
                albums.append(info)
            }
        }

        return albums
    }

    /// Fetches up to `limit` assets from a specific album, newest first.
    public func fetchAssets(in collection: PHAssetCollection, limit: Int = 200) async -> [PHAsset] {
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

    /// Resolves `PHAsset` instances from local identifiers. Used after
    /// `PHPickerViewController` returns identifiers for the user's selection.
    public func fetchAssets(withLocalIdentifiers identifiers: [String]) async -> [PHAsset] {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    // MARK: - Private helpers

    private func makeAlbumInfo(from collection: PHAssetCollection) -> AlbumInfo? {
        let options = PHFetchOptions()
        let fetchResult = PHAsset.fetchAssets(in: collection, options: options)

        let icon: String
        switch collection.assetCollectionSubtype {
        case .smartAlbumUserLibrary: icon = "photo.on.rectangle"
        case .smartAlbumFavorites:   icon = "heart.fill"
        case .smartAlbumVideos:      icon = "video.fill"
        case .smartAlbumPanoramas:   icon = "mountain.2.fill"
        case .smartAlbumBursts:      icon = "rectangle.stack.fill"
        case .smartAlbumScreenshots: icon = "iphone"
        default:                     icon = "folder.fill"
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
