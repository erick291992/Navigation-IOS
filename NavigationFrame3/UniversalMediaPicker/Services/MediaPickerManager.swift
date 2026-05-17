import SwiftUI
import PhotosUI
import AVFoundation

/// Handles the low-level processing of media assets into Unified MediaItem objects.
///
/// **Isolation note**: no `@MainActor` anywhere on this class. The instance
/// methods (`process(...)`) are nonisolated async, so per SE-0338 their
/// bodies run on the cooperative concurrent executor (background pool).
/// JPEG encoding, thumbnail generation, and video frame extraction all
/// stay off the main thread while still being called naturally with
/// `try await pickerManager.process(...)` from `@MainActor` view models —
/// the await suspends the caller on main, the work runs on background,
/// then the caller resumes on main when done.
public class MediaPickerManager {
    public static let shared = MediaPickerManager()

    private let photoKit = PhotoKitService.shared

    private init() {}
    
    /// Processes a PhotosPickerItem into a MediaItem.
    public func process(_ item: PhotosPickerItem) async throws -> MediaItem {
        // Handle Video
        if item.supportedContentTypes.contains(.movie) || item.supportedContentTypes.contains(.video) {
            return try await processVideo(item)
        }
        
        // Handle Image
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw MediaPickerError.loadFailed
        }
        
        guard let image = UIImage(data: data) else {
            throw MediaPickerError.invalidData
        }
        
        // Generate high-quality thumbnail
        let thumbnail = generateThumbnail(for: image)
        
        let mediaItem = MediaItem(data: data, thumbnail: thumbnail, contentType: .image, originalURL: nil)
        return mediaItem
    }

    /// Processes an array of PhotosPickerItems into MediaItems.
    public func process(_ items: [PhotosPickerItem]) async throws -> [MediaItem] {
        var results: [MediaItem] = []
        for item in items {
            let processed = try await process(item)
            results.append(processed)
        }
        return results
    }
    
    /// Processes a UIImage (from camera) into a MediaItem.
    public func process(_ image: UIImage) async throws -> MediaItem {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw MediaPickerError.conversionFailed
        }
        
        let thumbnail = generateThumbnail(for: image)
        
        let mediaItem = MediaItem(data: data, thumbnail: thumbnail, contentType: .image, originalURL: nil)
        return mediaItem
    }

    /// Processes a single PHAsset into a MediaItem.
    public func process(_ asset: PHAsset) async throws -> MediaItem {
        let image = await withCheckedContinuation { continuation in
            photoKit.loadThumbnail(for: asset, size: CGSize(width: 2000, height: 2000)) { img in
                continuation.resume(returning: img)
            }
        }
        
        guard let image = image else {
            throw MediaPickerError.loadFailed
        }
        
        // Use the existing image processing pipeline
        return try await process(image)
    }
    
    /// Processes an array of PHAssets into MediaItems.
    public func process(_ assets: [PHAsset]) async throws -> [MediaItem] {
        var results: [MediaItem] = []
        for asset in assets {
            if let processed = try? await process(asset) {
                results.append(processed)
            }
        }
        return results
    }
    
    // MARK: - Private Helpers
    
    private func processVideo(_ item: PhotosPickerItem) async throws -> MediaItem {
        guard let movie = try await item.loadTransferable(type: VideoPickerTransferable.self) else {
            throw MediaPickerError.loadFailed
        }
        
        let url = movie.url
        let data = try Data(contentsOf: url)
        
        // Generate thumbnail from video
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
        let thumbnail = UIImage(cgImage: cgImage)
        
        let mediaItem = MediaItem(data: data, thumbnail: thumbnail, contentType: .video, originalURL: url)
        return mediaItem
    }
    
    private func generateThumbnail(for image: UIImage) -> UIImage {
        let size: CGFloat = 600 // High quality but optimized
        let imageSize = image.size
        let side = min(imageSize.width, imageSize.height)
        
        let rect = CGRect(
            x: (imageSize.width - side) / 2,
            y: (imageSize.height - side) / 2,
            width: side,
            height: side
        )
        
        // 1. Crop to square
        guard let cgImage = image.cgImage?.cropping(to: rect) else { return image }
        let croppedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        
        // 2. Resize to target size
        let targetSize = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

/// Helper struct to load video from PhotosPicker
struct VideoPickerTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: copy.path) {
                try? FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return VideoPickerTransferable(url: copy)
        }
    }
}

public enum MediaPickerError: Error {
    case loadFailed
    case invalidData
    case conversionFailed
}
