import SwiftUI
import PhotosUI
import Photos

/// The Headless Engine (Tier 3) — provides raw media processing without UI components.
@MainActor
public class MediaPickerEngine {
    public static let shared = MediaPickerEngine()
    
    private let manager = MediaPickerManager.shared
    
    private init() {}
    
    /// Processes a PhotosPickerItem into a MediaItem.
    public func process(_ item: PhotosPickerItem) async throws -> MediaItem {
        return try await manager.process(item)
    }
    
    /// Processes multiple PhotosPickerItems into MediaItems.
    public func process(_ items: [PhotosPickerItem]) async throws -> [MediaItem] {
        return try await manager.process(items)
    }
    
    /// Processes a raw UIImage into a MediaItem.
    public func process(_ image: UIImage) async throws -> MediaItem {
        return try await manager.process(image)
    }
    
    /// Processes a single PHAsset into a MediaItem.
    public func process(_ asset: PHAsset) async throws -> MediaItem {
        return try await manager.process(asset)
    }
    
    /// Processes an array of PHAssets into MediaItems.
    public func process(_ assets: [PHAsset]) async throws -> [MediaItem] {
        return try await manager.process(assets)
    }
}
