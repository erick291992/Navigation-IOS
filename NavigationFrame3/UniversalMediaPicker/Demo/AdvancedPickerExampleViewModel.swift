import SwiftUI
import Photos
import Observation

// MARK: - Tier 3 Advanced Grid ViewModel
// Proves developers can build their own entirely custom grid UI
// utilizing AssetGridViewModel for fetching and MediaPickerEngine for processing.

@MainActor
@Observable
class AdvancedPickerExampleViewModel {
    
    // Core Managers (constructor-default DI)
    private let engine: MediaPickerEngine
    
    // We leverage AssetGridViewModel simply as a pure data source for PHAssets
    // meaning the developer doesn't have to write lower-level PhotoKit fetching logic themselves.
    let gridModel: AssetGridViewModel
    
    var flowState: FlowState = .idle
    var finishedItems: [MediaItem] = []
    
    var itemsToCrop: [MediaItem] = []
    var croppedResults: [Int: UIImage] = [:]
    
    var cropMode: MediaCrop = .square
    var maxSelection: Int
    
    enum FlowState: Equatable {
        case idle
        case processing
        case cropping(index: Int, total: Int)
    }
    
    init(maxSelection: Int = 3, engine: MediaPickerEngine = .shared) {
        self.maxSelection = maxSelection
        self.engine = engine
        self.gridModel = AssetGridViewModel(selectionLimit: maxSelection)
        self.gridModel.trigger(.loadInitialData) // Fetch photos immediately
    }
    
    // MARK: - Actions
    
    func selectAsset(_ asset: GridAsset) {
        gridModel.trigger(.toggleAssetSelection(asset))
    }
    
    // The developer calls this when the user taps their custom "Next" button
    func processSelectedAssets() {
        let assets = gridModel.state.selectedAssets
        guard !assets.isEmpty else { return }
        
        flowState = .processing
        
        Task {
            do {
                // Extract PHAssets from GridAsset wrappers
                let phAssets = assets.compactMap { $0.phAsset }
                
                // Pass raw PHAssets straight to the Tier 3 Engine!
                let processed = try await engine.process(phAssets)
                
                await MainActor.run {
                    self.itemsToCrop = processed
                    self.croppedResults = [:]
                    self.advanceToNextUncropped()
                }
            } catch {
                await MainActor.run {
                    self.flowState = .idle
                }
            }
        }
    }
    
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
    
    func cancelFlow() {
        flowState = .idle
        itemsToCrop = []
        croppedResults = [:]
    }
    
    private func advanceToNextUncropped() {
        for i in 0..<itemsToCrop.count {
            if croppedResults[i] == nil {
                flowState = .cropping(index: i, total: itemsToCrop.count)
                return
            }
        }
        
        // Done cropping
        flowState = .idle
        itemsToCrop = []
        croppedResults = [:]
        gridModel.trigger(.clearSelection)
    }
}
