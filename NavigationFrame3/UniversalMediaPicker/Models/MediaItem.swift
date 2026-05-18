import SwiftUI

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
