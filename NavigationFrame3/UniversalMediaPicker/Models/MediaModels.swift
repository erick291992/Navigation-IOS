import SwiftUI
import PhotosUI

/// Represents a selected media item from the picker.
public struct MediaItem: Identifiable, Hashable {
    public let id = UUID()
    
    /// The raw data of the media (Image or Video data).
    public let data: Data
    
    /// A high-quality thumbnail for UI display.
    public let thumbnail: UIImage
    
    /// The type of content (image or video).
    public let contentType: MediaContentType
    
    /// The original URL if available (important for videos).
    public let originalURL: URL?
    
    public enum MediaContentType: Hashable {
        case image
        case video
    }
}

/// Defines the supported crop modes.
public enum MediaCrop: Hashable {
    case square      // 1:1
    case portrait    // 4:5 (Instagram standard)
    case landscape   // 16:9
    case circle      // 1:1 circular mask
    case freeform    // User-adjustable
    case none        // No cropping
    
    public var title: String {
        switch self {
        case .square: return "Square"
        case .portrait: return "4:5"
        case .landscape: return "16:9"
        case .circle: return "Circle"
        case .freeform: return "Free"
        case .none: return "Original"
        }
    }
    
    public func size(in container: CGSize) -> CGSize? {
        let side = min(container.width, container.height) * 0.9
        switch self {
        case .square, .circle:
            return CGSize(width: side, height: side)
        case .portrait:
            return CGSize(width: side * 0.8, height: side)
        case .landscape:
            return CGSize(width: side, height: side * (9.0/16.0))
        case .freeform:
            return nil
        case .none:
            return container
        }
    }
}

/// The internal state of the picker.
public struct MediaPickerState {
    public enum FlowState: Equatable {
        case idle
        case processing
        case cropping(index: Int, total: Int)
        case finished
    }
    
    public var flowState: FlowState = .idle
    public var items: [MediaItem] = []      // The full set
    public var croppedResults: [Int: UIImage] = [:] // Completed crops by index
    public var errorMessage: String?
}



/// Configuration for the Universal Media Picker.
public struct MediaPickerConfiguration {
    public let selectionLimit: Int
    public let allowedTypes: [PHPickerFilter]
    public let crop: MediaCrop
    public let showCamera: Bool
    public let style: MediaPickerStyle
    
    public init(
        selectionLimit: Int = 1,
        allowedTypes: [PHPickerFilter] = [.images, .videos],
        crop: MediaCrop = .freeform,
        showCamera: Bool = true,
        style: MediaPickerStyle = .default
    ) {
        self.selectionLimit = selectionLimit
        self.allowedTypes = allowedTypes
        self.crop = crop
        self.showCamera = showCamera
        self.style = style
    }
}
