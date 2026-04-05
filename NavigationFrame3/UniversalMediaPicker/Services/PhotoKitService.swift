import Foundation
import Photos
import UIKit

/// A lightweight service to fetch recent assets from the user's photo library.
public class PhotoKitService: ObservableObject {
    public static let shared = PhotoKitService()
    
    @Published public var recentAssets: [PHAsset] = []
    
    private init() {}
    
    /// Requests permission and fetches the last X assets.
    public func fetchRecentAssets(limit: Int = 20) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            guard status == .authorized || status == .limited else { return }
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = limit
            
            let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            var assets: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
            
            DispatchQueue.main.async {
                self?.recentAssets = assets
            }
        }
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
