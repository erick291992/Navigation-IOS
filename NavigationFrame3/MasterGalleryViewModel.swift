import SwiftUI
import PhotosUI

@Observable
class MasterGalleryViewModel {
    var pickedItems: [MediaItem] = []
    var showModifierPicker = false
    @ObservationIgnored
    var pickerId = UUID()
    var cropMode: MediaCrop = .square
    var selectionLimit: Int = 1
    
    // Tier 3: Headless State
    var flowState: MediaPickerState.FlowState = .idle
    var headlessSelection: [PhotosPickerItem] = []
    var headlessItems: [MediaItem] = []
    var headlessResults: [Int: UIImage] = [:]
    
    // Style B: Geometric Picker (Testing)
    var showGeometricPicker = false
    
    func openPicker(crop: MediaCrop, limit: Int = 1) {
        self.cropMode = crop
        self.selectionLimit = limit
        self.pickerId = UUID()
        self.showModifierPicker = true
    }
    
    func handlePickerResult(_ items: [MediaItem]) {
        pickedItems.append(contentsOf: items)
        showModifierPicker = false
    }
    
    func cancelPicker() {
        showModifierPicker = false
    }
    
    // Tier 3: Headless Logic
    func didSelectHeadless(_ items: [PhotosPickerItem]) {
        print("📸 PhotosPicker selected \(items.count) items")
        guard !items.isEmpty else { return }
        
        flowState = .processing
        Task {
            do {
                print("🔄 Starting headless processing...")
                let processed = try await MediaPickerEngine.shared.process(items)
                print("✅ Processed \(processed.count) items")
                
                await MainActor.run {
                    self.headlessSelection = []
                    self.headlessItems = processed
                    self.headlessResults = [:]
                    print("🏁 Transitioning to cropping flow")
                    self.processNextHeadless()
                }
            } catch {
                print("❌ Headless processing failed: \(error)")
                await MainActor.run { 
                    self.flowState = .idle 
                    self.headlessSelection = []
                }
            }
        }
    }
    
    func handleCameraCapture(_ image: UIImage) {
        print("📸 Camera captured image")
        flowState = .processing
        Task {
            let manager = MediaPickerManager.shared
            do {
                let item = try await manager.process(image)
                await MainActor.run {
                    self.headlessItems = [item]
                    self.headlessResults = [:]
                    print("🏁 Transitioning to camera cropping")
                    self.flowState = .cropping(index: 0, total: 1)
                }
            } catch {
                print("❌ Camera processing failed: \(error)")
                await MainActor.run { self.flowState = .idle }
            }
        }
    }
    
    func jumpTo(index: Int) {
        print("🔀 Jumping to index \(index)")
        flowState = .cropping(index: index, total: headlessItems.count)
    }
    
    func processNextHeadless() {
        print("🔍 Searching for next uncropped item...")
        for i in 0..<headlessItems.count {
            if headlessResults[i] == nil {
                print("🎯 Found uncropped at index \(i)")
                flowState = .cropping(index: i, total: headlessItems.count)
                return
            }
        }
        print("✅ All items processed. Finishing.")
        flowState = .idle
        // Don't clear headlessItems yet if you want to use them for something else, 
        // but for now we follow the "finished" logic.
        headlessItems = []
        headlessResults = [:]
    }
    
    func handleCropResult(_ image: UIImage, at index: Int) {
        print("✂️ Crop finished for index \(index)")
        Task {
            let processed = try? await MediaPickerEngine.shared.process(image)
            await MainActor.run {
                if let processed = processed {
                    print("✅ Saved crop for index \(index)")
                    self.headlessResults[index] = processed.thumbnail
                    self.pickedItems.append(processed)
                    self.processNextHeadless()
                } else {
                    print("⚠️ Failed to process crop result at \(index), skipping...")
                    // If processing fails, we should still try the next one so we don't get stuck
                    self.processNextHeadless()
                }
            }
        }
    }

    func startGeometricFlow(_ items: [MediaItem]) {
        print("💎 Style B bridging to Cropping Flow...")
        self.headlessItems = items
        self.headlessResults = [:]
        self.processNextHeadless()
    }
}
