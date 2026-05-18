import Photos

/// A polymorphic wrapper for items displayed in the grid.
public enum GridAsset: Identifiable, Hashable {
    case phAsset(PHAsset)
    case mediaItem(MediaItem)

    public var id: String {
        switch self {
        case .phAsset(let asset): return asset.localIdentifier
        case .mediaItem(let item): return item.id.uuidString
        }
    }

    public var phAsset: PHAsset? {
        if case .phAsset(let asset) = self { return asset }
        return nil
    }

    public var mediaItem: MediaItem? {
        if case .mediaItem(let item) = self { return item }
        return nil
    }
}
