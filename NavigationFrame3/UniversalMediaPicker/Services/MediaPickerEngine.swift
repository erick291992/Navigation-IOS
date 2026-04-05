import SwiftUI
import PhotosUI

/// The Headless Engine (Tier 3) — provides raw media processing without UI components.
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
        var results: [MediaItem] = []
        for item in items {
            let processed = try await manager.process(item)
            results.append(processed)
        }
        return results
    }
    
    /// Processes a raw UIImage into a MediaItem.
    public func process(_ image: UIImage) async throws -> MediaItem {
        return try await manager.process(image)
    }
}
