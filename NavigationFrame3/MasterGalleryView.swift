import SwiftUI
import PhotosUI

struct MasterGalleryView: View {
    @Environment(\.navigationManager) var navigationManager: NavigationManager
    @State private var vm = MasterGalleryViewModel()
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 8) {
                        Text("💎 Master Gallery")
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("The Ultimate Media Picker Suite")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary.opacity(0.8))
                    }
                    .padding(.top, 40)

                    if !vm.pickedItems.isEmpty {
                        MediaPickerResultGallery(items: vm.pickedItems)
                    }
                    
                    // Elite Integration Section
                    VStack(spacing: 24) {
                        Text("🛠️ Integration Tiers")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(spacing: 12) {
                            // TIER 1 & 2: Frictionless Modifier Flow
                            MediaPickerButton(title: "Tier 1 & 2: Instant Picker", icon: "sparkles") {
                                vm.showModifierPicker = true
                            }
                            .tint(.blue)
                            
                            // TIER 3: Custom Headless Flow
                            HStack(spacing: 12) {
                                PhotosPicker(selection: $vm.headlessSelection, maxSelectionCount: 3, matching: .images) {
                                    MediaPickerButtonLabel(title: "Tier 3: Custom Library", icon: "photo.stack")
                                }
                                .onChange(of: vm.headlessSelection) { _, items in
                                    vm.didSelectHeadless(items)
                                }
                                
                                MediaPickerButton(title: "Tier 3: Custom Camera", icon: "camera.fill") {
                                    vm.flowState = .camera
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        // 🧪 ELITE FLOW: Frictionless Modifier (Handles Selection -> Crop sequence)
        .mediaPicker(
            isPresented: $vm.showModifierPicker,
            configuration: .init(crop: .square, style: .pinkSleek),
            onCompletion: { items in
                vm.handlePickerResult(items)
            }
        )
        // 🧪 TIER 3: Headless Engine - Custom Crop View
        .sheet(isPresented: Binding(
            get: { if case .cropping = vm.flowState { return true } else { return false } },
            set: { if !$0 { vm.flowState = .idle } }
        )) {
            if case .cropping(let index, let total) = vm.flowState, index < vm.headlessItems.count {
                let item = vm.headlessItems[index]
                CropView(
                    item: item,
                    crop: .freeform,
                    subtitle: "Image \(index + 1)/\(total)",
                    thumbnails: vm.headlessItems.map { $0.thumbnail },
                    activeIndex: index,
                    croppedIndices: Set(vm.headlessResults.keys),
                    onJump: { vm.jumpTo(index: $0) },
                    onDone: { cropped in
                        vm.handleCropResult(cropped, at: index)
                    },
                    onCancel: {
                        vm.flowState = .idle
                    }
                )
            }
        }
        // 🧪 TIER 3: Headless Engine - Custom Camera
        .fullScreenCover(isPresented: Binding(
            get: { if case .camera = vm.flowState { return true } else { return false } },
            set: { if !$0 { vm.flowState = .idle } }
        )) {
            CameraPicker(
                onCapture: { image in
                    vm.handleCameraCapture(image)
                },
                onCancel: {
                    vm.flowState = .idle
                }
            )
            .ignoresSafeArea()
        }
    }
}
