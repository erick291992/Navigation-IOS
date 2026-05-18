import SwiftUI

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
