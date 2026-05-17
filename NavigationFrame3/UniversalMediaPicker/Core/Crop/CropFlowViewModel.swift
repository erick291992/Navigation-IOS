import SwiftUI
import PhotosUI
import Observation

@MainActor
@Observable
public class CropFlowViewModel {
    // MARK: - Configuration & Callbacks
    private let manager: MediaPickerManager
    private let historyManager: MediaHistoryManager
    private let configuration: MediaPickerConfiguration
    private var onCompletion: ([MediaItem]) -> Void
    private var onCancel: () -> Void
    
    // MARK: - Public State
    public var items: [MediaItem] = []
    public var croppedResults: [Int: UIImage] = [:]
    public var flowState: FlowState = .idle
    public var errorMessage: String?
    
    public enum FlowState: Equatable {
        case idle
        case processing
        case camera
        case cropping(index: Int, total: Int)
        case finished
    }
    
    public init(
        configuration: MediaPickerConfiguration,
        initialItems: [MediaItem] = [],
        manager: MediaPickerManager = .shared,
        historyManager: MediaHistoryManager = .shared,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.manager = manager
        self.historyManager = historyManager
        self.onCompletion = onCompletion
        self.onCancel = onCancel
        self.items = initialItems
        
        if !initialItems.isEmpty {
            self.moveToNextUncropped()
        }
    }
    
    // MARK: - Actions
    
    public func handleCapture(_ image: UIImage) {
        flowState = .processing
        Task {
            do {
                let mediaItem = try await manager.process(image)
                await MainActor.run {
                    self.items = [mediaItem]
                    self.moveToNextUncropped()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to process photo"
                    self.flowState = .idle
                }
            }
        }
    }
    
    public func finishCrop(item: MediaItem, index: Int) {
        croppedResults[index] = item.thumbnail
        moveToNextUncropped()
    }
    
    public func jumpTo(index: Int) {
        guard index < items.count else { return }
        flowState = .cropping(index: index, total: items.count)
    }
    
    public func requestCamera() {
        flowState = .camera
    }
    
    public func cancelCrop() {
        flowState = .idle
    }
    
    public func dismiss() {
        items = []
        croppedResults = [:]
        flowState = .idle
        onCancel()
    }
    
    // MARK: - Private Logic
    
    private func moveToNextUncropped() {
        for i in 0..<items.count {
            if croppedResults[i] == nil {
                flowState = .cropping(index: i, total: items.count)
                return
            }
        }
        finalize()
    }
    
    private func finalize() {
        let finalItems = items.enumerated().compactMap { index, originalItem in
            if let croppedImage = croppedResults[index] {
                return MediaItem(
                    data: croppedImage.jpegData(compressionQuality: 0.8) ?? originalItem.data,
                    thumbnail: croppedImage,
                    contentType: originalItem.contentType,
                    originalURL: originalItem.originalURL
                )
            }
            return nil
        }
        
        historyManager.addToHistory(finalItems)
        onCompletion(finalItems)
        items = []
        croppedResults = [:]
        flowState = .finished
    }
}
