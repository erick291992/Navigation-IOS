import SwiftUI
import PhotosUI
import Observation


/// The View's "Actions" — restricted set of triggers.
public enum MediaPickerAction {
    case didSelect([PhotosPickerItem])
    case didCapture(UIImage)
    case didFinishCrop(item: MediaItem, index: Int)
    case didCancelCrop
    case requestCamera
    case requestLibrary
    case dismiss
}

@Observable
public class MediaPickerViewModel {
    // MARK: - Internal Storage
    private let manager: MediaPickerManager
    private let configuration: MediaPickerConfiguration
    private var onCompletion: ([MediaItem]) -> Void
    private var onCancel: () -> Void
    
    // MARK: - Public State (The Lens)
    public var state = MediaPickerState()
    
    public init(
        configuration: MediaPickerConfiguration,
        initialItems: [MediaItem] = [],
        manager: MediaPickerManager = .shared,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.manager = manager
        self.onCompletion = onCompletion
        self.onCancel = onCancel
        self.state.items = initialItems
        
        if !initialItems.isEmpty {
            self.moveToNextUncropped()
        }
    }
    
    // MARK: - Action Handler
    public func trigger(_ action: MediaPickerAction) {
        switch action {
        case .didSelect(let items):
            handleLibrarySelection(items)
            
        case .didCapture(let image):
            handleCameraCapture(image)
            
        case .didFinishCrop(let item, let index):
            state.croppedResults[index] = item.thumbnail
            // Auto-advance to next uncropped or finish
            moveToNextUncropped()
            
        case .requestCamera:
            state.flowState = .camera
            
        case .didCancelCrop:
            state.flowState = .idle
            
        case .requestLibrary:
            state.flowState = .idle
            
        case .dismiss:
            state.items = []
            state.croppedResults = [:]
            state.flowState = .idle
            onCancel()
        }
    }
    
    public func jumpTo(index: Int) {
        guard index < state.items.count else { return }
        state.flowState = .cropping(index: index, total: state.items.count)
    }
    
    // MARK: - Private Logic
    
    private func handleLibrarySelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        state.flowState = .processing
        
        Task {
            do {
                let processed = try await manager.process(items.prefix(configuration.selectionLimit).map { $0 })
                await MainActor.run {
                    self.state.items = processed
                    self.moveToNextUncropped()
                }
            } catch {
                await MainActor.run {
                    state.errorMessage = "Failed to load media"
                    state.flowState = .idle
                }
            }
        }
    }
    
    private func handleCameraCapture(_ image: UIImage) {
        state.flowState = .processing
        
        Task {
            do {
                let mediaItem = try await manager.process(image)
                await MainActor.run {
                    self.state.items = [mediaItem]
                    self.moveToNextUncropped()
                }
            } catch {
                await MainActor.run {
                    state.errorMessage = "Failed to process photo"
                    state.flowState = .idle
                }
            }
        }
    }
    
    private func moveToNextUncropped() {
        // Find the first index that isn't cropped yet
        for i in 0..<state.items.count {
            if state.croppedResults[i] == nil {
                state.flowState = .cropping(index: i, total: state.items.count)
                return
            }
        }
        
        // If all are cropped, we are finish
        finalize()
    }
    
    private func finalize() {
        // Build final list (in original order)
        let finalItems = state.items.enumerated().compactMap { index, originalItem in
            if let croppedImage = state.croppedResults[index] {
                return MediaItem(
                    data: croppedImage.jpegData(compressionQuality: 0.8) ?? originalItem.data,
                    thumbnail: croppedImage,
                    contentType: originalItem.contentType,
                    originalURL: originalItem.originalURL
                )
            }
            return nil
        }
        
        onCompletion(finalItems)
        state.items = []
        state.croppedResults = [:]
        state.flowState = .idle
    }

    public func cancel() {
        onCancel()
    }
}
