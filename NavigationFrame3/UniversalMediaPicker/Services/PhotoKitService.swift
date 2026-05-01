import Foundation
import Photos
import UIKit
import Observation

/// A lightweight service to fetch recent assets from the user's photo library.
@MainActor
@Observable
public class PhotoKitService {
    public static let shared = PhotoKitService()
    
    public var recentAssets: [PHAsset] = []
    public var authStatus: PHAuthorizationStatus = .notDetermined
    
    private init() {
        self.authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
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
        
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootVC)
    }
    
    private func performFetch(limit: Int) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = limit
        
        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
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
}
