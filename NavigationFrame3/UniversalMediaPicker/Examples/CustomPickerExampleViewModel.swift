import SwiftUI
import PhotosUI

// MARK: - Tier 3 ViewModel
// This is everything a developer needs to manage the picker engine state.
// No Elite UI dependencies — just raw MediaPickerManager + CropView.

@Observable
class CustomPickerExampleViewModel {

    // MARK: - Services (constructor-default DI)
    private let manager: MediaPickerManager

    init(manager: MediaPickerManager = .shared) {
        self.manager = manager
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    // MARK: - Fire-and-forget Task storage (see CODING_GUIDELINES.md §3)
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

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

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let processed = try await self.manager.process(items)
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
        tasks.append(task)
    }

    /// Called when CameraPicker returns a captured image.
    func didCapturePhoto(_ image: UIImage) {
        flowState = .processing
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let item = try await self.manager.process(image)
                await MainActor.run {
                    self.itemsToCrop = [item]
                    self.croppedResults = [:]
                    self.flowState = .cropping(index: 0, total: 1)
                }
            } catch {
                await MainActor.run { self.flowState = .idle }
            }
        }
        tasks.append(task)
    }

    /// Called when CropView finishes cropping one image.
    func didFinishCrop(_ croppedImage: UIImage, at index: Int) {
        let task = Task { [weak self] in
            guard let self else { return }
            let result = try? await self.manager.process(croppedImage)
            await MainActor.run {
                if let result = result {
                    self.croppedResults[index] = result.thumbnail
                    self.finishedItems.append(result)
                }
                self.advanceToNextUncropped()
            }
        }
        tasks.append(task)
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
