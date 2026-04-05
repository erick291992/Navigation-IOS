import SwiftUI
import PhotosUI

/// Handles the low-level processing of media assets into Unified MediaItem objects.
public class MediaPickerManager {
    public static let shared = MediaPickerManager()
    
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
        
        return MediaItem(
            data: data,
            thumbnail: thumbnail,
            contentType: .image,
            originalURL: nil
        )
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
        
        return MediaItem(
            data: data,
            thumbnail: thumbnail,
            contentType: .image,
            originalURL: nil
        )
    }
    
    // MARK: - Private Helpers
    
    private func processVideo(_ item: PhotosPickerItem) async throws -> MediaItem {
        // For videos, we need the file URL to generate a thumbnail and get the data
        // Note: In a production app, we'd use PHAsset to get the URL more reliably, 
        // but loadTransferable(type: URL.self) works for the system picker results.
        
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
        
        return MediaItem(
            data: data,
            thumbnail: thumbnail,
            contentType: .video,
            originalURL: url
        )
    }
    
    private func generateThumbnail(for image: UIImage) -> UIImage {
        let maxSide: CGFloat = 800
        let ratio = image.size.width / image.size.height
        
        var newSize: CGSize
        if ratio > 1 {
            newSize = CGSize(width: maxSide, height: maxSide / ratio)
        } else {
            newSize = CGSize(width: maxSide * ratio, height: maxSide)
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
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
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return VideoPickerTransferable(url: copy)
        }
    }
}

enum MediaPickerError: Error {
    case loadFailed
    case invalidData
    case conversionFailed
}
