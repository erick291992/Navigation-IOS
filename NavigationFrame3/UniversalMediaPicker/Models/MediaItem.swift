import SwiftUI

/// Represents a selected media item from the picker.
///
/// Identity (`id`) is a per-instance UUID for `Identifiable` conformance
/// (e.g. `ForEach`). Equality + hashing are **content-based** — two items
/// with identical `data` + `contentType` + `originalURL` compare equal even
/// across separate `process(...)` calls. This is what lets `MediaHistoryManager`
/// deduplicate via `==` and `Set<MediaItem>` collapse duplicates by content.
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

    public static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
        lhs.data == rhs.data
            && lhs.contentType == rhs.contentType
            && lhs.originalURL == rhs.originalURL
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(data)
        hasher.combine(contentType)
        hasher.combine(originalURL)
    }
}
