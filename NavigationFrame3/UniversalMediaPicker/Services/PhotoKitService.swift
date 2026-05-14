import Foundation
import Photos
import PhotosUI
import UIKit
import Observation

/// Process-wide thumbnail cache. Keys include `modificationDate` so an
/// in-place edit in `Photos.app` (crop, markup, filter — same identifier,
/// new pixels) produces a cache miss and a fresh fetch. Without this, the
/// grid would happily serve pre-edit pixels until the entry was evicted.
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

/// A lightweight service to fetch recent assets from the user's photo library.
@MainActor
@Observable
public class PhotoKitService: NSObject, PHPhotoLibraryChangeObserver {
    public static let shared = PhotoKitService()
    
    public var recentAssets: [PHAsset] = []
    public var authStatus: PHAuthorizationStatus = .notDetermined
    private var fetchResult: PHFetchResult<PHAsset>?
    
    private override init() {
        super.init()
        self.authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        PHPhotoLibrary.shared().register(self)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    /// Silently updates the authorization status without requesting it.
    public func updateAuthStatus() {
        let newStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard newStatus != authStatus else { return }
        authStatus = newStatus
    }
    
    /// Requests permission and fetches the last X assets.
    public func fetchRecentAssets(limit: Int = 30) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        setAuthStatus(status)

        if status != .authorized && status != .limited {
            clearRecentAssetsIfNeeded()
        }

        switch status {
        case .authorized, .limited:
            self.performFetch(limit: limit)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                Task { @MainActor in
                    self.setAuthStatus(newStatus)
                    if newStatus == .authorized || newStatus == .limited {
                        self.performFetch(limit: limit)
                    } else {
                        self.clearRecentAssetsIfNeeded()
                    }
                }
            }
        default:
            print("⚠️ Photo Library access denied")
            clearRecentAssetsIfNeeded()
        }
    }

    // Equality-guarded setters. @Observable instruments every setter call —
    // writing the same value still notifies subscribers and cascades a re-eval
    // through the body (which is what produced the flicker on popup dismiss,
    // even though the value never changed).
    private func setAuthStatus(_ newStatus: PHAuthorizationStatus) {
        guard newStatus != authStatus else { return }
        authStatus = newStatus
    }

    private func clearRecentAssetsIfNeeded() {
        guard !recentAssets.isEmpty else { return }
        recentAssets = []
    }
    
    /// Opens the native Apple limited library picker.
    public func openLimitedPicker() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        
        let topVC = findTopViewController(from: rootVC)
        
        if #available(iOS 15.0, *) {
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: topVC) { _ in
                Task { @MainActor in
                    self.fetchRecentAssets()
                }
            }
        } else {
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: topVC)
        }
    }
    
    /// Opens the system picker via UIKit to avoid SwiftUI presentation collisions.
    public func openSystemPicker(selectionLimit: Int, completion: @escaping ([PHAsset]) -> Void) {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = selectionLimit
        config.filter = .images
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = PhotoKitServicePickerDelegate.shared // We'll need a delegate
        PhotoKitServicePickerDelegate.shared.completion = completion
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        
        let topVC = findTopViewController(from: rootVC)
        topVC.present(picker, animated: true)
    }
    
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
    
    private func performFetch(limit: Int) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = limit
        
        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        self.fetchResult = result
        self.updateAssets(from: result)
    }
    
    private func updateAssets(from result: PHFetchResult<PHAsset>) {
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        // Defensive: never shrink a populated list to empty (parity with
        // AssetGridViewModel.refreshCurrentAssets). PhotoKit's Limited
        // Access selection set is briefly empty during popup dismiss; we
        // don't want the top viewfinder's recentAssets to flash blank
        // either, even though previewAsset masking currently hides it.
        if assets.isEmpty && !self.recentAssets.isEmpty {
            return
        }

        // Skip assignment if the data hasn't actually changed.
        // Replacing the array with an identical copy forces SwiftUI
        // to destroy and recreate every grid cell, causing flicker.
        let newIDs = assets.map(\.localIdentifier)
        let oldIDs = self.recentAssets.map(\.localIdentifier)
        guard newIDs != oldIDs else { return }

        self.recentAssets = assets
    }
    
    /// Loads a thumbnail for a given asset.
    /// Consults the process-wide `ThumbnailCache` first — on hit, `completion`
    /// runs synchronously inline so the caller can paint without an async hop.
    public func loadThumbnail(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let key = ThumbnailCache.key(for: asset)
        if let cached = ThumbnailCache.shared.object(forKey: key) {
            completion(cached)
            return
        }

        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat

        manager.requestImage(for: asset,
                             targetSize: size,
                             contentMode: .aspectFill,
                             options: options) { image, _ in
            if let image = image {
                ThumbnailCache.shared.setObject(image, forKey: key)
            }
            completion(image)
        }
    }
    
    // MARK: - PHPhotoLibraryChangeObserver
    
    nonisolated public func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.updateAuthStatus()

            // Note: When using a fetchLimit, changeInstance.changeDetails(for:)
            // is unreliable and can miss newly inserted items or return nil.
            // We force a full refresh to guarantee the UI reflects the new state.
            if self.authStatus == .authorized || self.authStatus == .limited {
                self.fetchRecentAssets()
            }
        }
    }
}

class PhotoKitServicePickerDelegate: NSObject, PHPickerViewControllerDelegate {
    static let shared = PhotoKitServicePickerDelegate()
    var completion: (([PHAsset]) -> Void)?
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        let identifiers = results.compactMap(\.assetIdentifier)
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        completion?(assets)
    }
}
