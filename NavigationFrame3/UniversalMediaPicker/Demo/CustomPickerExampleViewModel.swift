import SwiftUI
import PhotosUI

// MARK: - Tier 3 ViewModel
// This is everything a developer needs to manage the picker engine state.
// No Elite UI dependencies — just raw MediaPickerEngine + CropView.

@Observable
class CustomPickerExampleViewModel {

    // MARK: - Services (constructor-default DI)
    private let engine: MediaPickerEngine

    init(engine: MediaPickerEngine = .shared) {
        self.engine = engine
    }

    // MARK: - Published State
    var finishedItems: [MediaItem] = []       // Final results the dev consumes
    var flowState: FlowState = .idle
    
    // MARK: - Internal Engine State
    var photosSelection: [PhotosPickerItem] = []  // System picker binding
    var itemsToCrop: [MediaItem] = []              // Queue waiting for crop
    var croppedResults: [Int: UIImage] = [:]       // Completed crops by index
    
    enum FlowState: Equatable {
        case idle
        case processing
        case cropping(index: Int, total: Int)
        case camera
    }
    
    // MARK: - Configuration (Developer Sets These)
    var cropMode: MediaCrop = .square
    var maxSelection: Int = 1
    
    // MARK: - Actions
    
    /// Called when the system PhotosPicker returns selected items.
    func didSelectPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        flowState = .processing
        
        Task {
            do {
                let processed = try await engine.process(items)
                await MainActor.run {
                    self.photosSelection = []     // Reset picker
                    self.itemsToCrop = processed
                    self.croppedResults = [:]
                    self.advanceToNextUncropped()
                }
            } catch {
                await MainActor.run {
                    self.flowState = .idle
                    self.photosSelection = []
                }
            }
        }
    }
    
    /// Called when CameraPicker returns a captured image.
    func didCapturePhoto(_ image: UIImage) {
        flowState = .processing
        Task {
            do {
                let item = try await engine.process(image)
                await MainActor.run {
                    self.itemsToCrop = [item]
                    self.croppedResults = [:]
                    self.flowState = .cropping(index: 0, total: 1)
                }
            } catch {
                await MainActor.run { self.flowState = .idle }
            }
        }
    }
    
    /// Called when CropView finishes cropping one image.
    func didFinishCrop(_ croppedImage: UIImage, at index: Int) {
        Task {
            let result = try? await engine.process(croppedImage)
            await MainActor.run {
                if let result = result {
                    self.croppedResults[index] = result.thumbnail
                    self.finishedItems.append(result)
                }
                self.advanceToNextUncropped()
            }
        }
    }
    
    /// Jump to a specific image in the crop queue (for multi-image strip navigation).
    func jumpToCropIndex(_ index: Int) {
        flowState = .cropping(index: index, total: itemsToCrop.count)
    }
    
    /// Cancel the entire flow and return to idle.
    func cancelFlow() {
        flowState = .idle
        itemsToCrop = []
        croppedResults = [:]
    }
    
    // MARK: - Private
    
    private func advanceToNextUncropped() {
        for i in 0..<itemsToCrop.count {
            if croppedResults[i] == nil {
                flowState = .cropping(index: i, total: itemsToCrop.count)
                return
            }
        }
        // All done — return to idle
        flowState = .idle
        itemsToCrop = []
        croppedResults = [:]
    }
}
