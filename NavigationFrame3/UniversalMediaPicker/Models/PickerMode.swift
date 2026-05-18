import Foundation

/// The three modes the picker can be in. Owned by `PickerViewModel` and passed
/// DOWN through the view tree as a `let` parameter; the mode bar fires an
/// `onModeSelect` callback UP to change it.
public enum PickerMode: Hashable, Sendable {
    case library
    case reuse
    case photo

    /// Display title for the mode bar.
    public var title: String {
        switch self {
        case .library: return "LIBRARY"
        case .reuse:   return "REUSE"
        case .photo:   return "PHOTO"
        }
    }
}
