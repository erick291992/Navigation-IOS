import SwiftUI

/// The internal state of the picker.
public struct MediaPickerState {
    public enum FlowState: Equatable {
        case idle
        case processing
        case camera
        case cropping(index: Int, total: Int)
        case finished
    }

    public var flowState: FlowState = .idle
    public var items: [MediaItem] = []      // The full set
    public var croppedResults: [Int: UIImage] = [:] // Completed crops by index
    public var errorMessage: String?
}
