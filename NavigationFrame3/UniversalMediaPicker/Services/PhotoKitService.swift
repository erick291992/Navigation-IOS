import Foundation
import Photos
import PhotosUI
import UIKit
import Observation

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
        self.authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    /// Requests permission and fetches the last X assets.
    public func fetchRecentAssets(limit: Int = 30) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authStatus = status
        
        if status != .authorized && status != .limited {
            self.recentAssets = []
        }
        
        switch status {
        case .authorized, .limited:
            self.performFetch(limit: limit)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                Task { @MainActor in
                    self.authStatus = newStatus
                    if newStatus == .authorized || newStatus == .limited {
                        self.performFetch(limit: limit)
                    } else {
                        self.recentAssets = []
                    }
                }
            }
        default:
            print("⚠️ Photo Library access denied")
            self.recentAssets = []
        }
    }
    
    /// Opens the native Apple limited library picker.
    public func openLimitedPicker() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        
        let topVC = findTopViewController(from: rootVC)
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: topVC)
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
        self.recentAssets = assets
    }
    
    /// Loads a thumbnail for a given asset.
    public func loadThumbnail(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        
        manager.requestImage(for: asset, 
                             targetSize: size, 
                             contentMode: .aspectFill, 
                             options: options) { image, _ in
            completion(image)
        }
    }
    
    // MARK: - PHPhotoLibraryChangeObserver
    
    nonisolated public func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.updateAuthStatus()
            
            if let result = self.fetchResult, let details = changeInstance.changeDetails(for: result) {
                // Surgical update of the fetch result
                let updatedResult = details.fetchResultAfterChanges
                self.fetchResult = updatedResult
                self.updateAssets(from: updatedResult)
            } else {
                // Full fallback refresh
                if self.authStatus == .authorized || self.authStatus == .limited {
                    self.fetchRecentAssets()
                }
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
