import SwiftUI
import PhotosUI

@Observable
class ViewBViewModel {
    var pickedItems: [MediaItem] = []
    var showPicker = false
    var showModifierPicker = false
    var pickerId = UUID()
    var cropMode: MediaCrop = .square
    var isCircular: Bool = false
    var selectionLimit: Int = 1
    
    // Tier 3 test: Headless
    var flowState: MediaPickerState.FlowState = .idle
    var headlessSelection: [PhotosPickerItem] = []
    var headlessItems: [MediaItem] = []
    var headlessResults: [Int: UIImage] = [:]
    
    // Tier 1 test: Drop-in picker
    func openPicker(crop: MediaCrop, circular: Bool = false, limit: Int = 1) {
        self.cropMode = circular ? .circle : crop
        self.isCircular = circular
        self.selectionLimit = limit
        self.pickerId = UUID()
        self.showPicker = true
    }
    
    func handlePickerResult(_ items: [MediaItem]) {
        pickedItems.append(contentsOf: items)
        showPicker = false
    }
    
    func cancelPicker() {
        showPicker = false
    }
    
    // Tier 3 logic
    func didSelectHeadless(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        flowState = .processing
        Task {
            do {
                let processed = try await MediaPickerEngine.shared.process(items)
                await MainActor.run {
                    self.headlessSelection = []
                    self.headlessItems = processed
                    self.headlessResults = [:]
                    self.processNextHeadless()
                }
            } catch {
                print("❌ Headless processing failed: \(error)")
                self.flowState = .idle
            }
        }
    }
    
    func jumpTo(index: Int) {
        flowState = .cropping(index: index, total: headlessItems.count)
    }
    
    func processNextHeadless() {
        // Find the first index that isn't cropped yet
        for i in 0..<headlessItems.count {
            if headlessResults[i] == nil {
                flowState = .cropping(index: i, total: headlessItems.count)
                return
            }
        }
        
        // If all are done
        flowState = .idle
        headlessItems = []
        headlessResults = [:]
    }
    
    func handleCropResult(_ image: UIImage, at index: Int) {
        Task {
            let processed = try? await MediaPickerEngine.shared.process(image)
            await MainActor.run {
                if let processed = processed {
                    self.headlessResults[index] = processed.thumbnail
                    self.pickedItems.append(processed)
                    self.processNextHeadless()
                }
            }
        }
    }
}
