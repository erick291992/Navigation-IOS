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
                        Text("💎 Unified Creator (V3)")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(.primary)
                            .padding(.top, 24)
                        
                        MediaPickerButton(title: "Open Elite Picker", icon: "sparkles") {
                            vm.showModifierPicker = true
                        }
                        
                        Divider().padding(.vertical, 8)
                        
                        Text("🛠️ Modular Building Blocks (Tier 3)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.top, 16)
                        
                        HStack(spacing: 16) {
                            MediaPickerNavCard(
                                title: "Custom Library",
                                subtitle: "Headless selection",
                                icon: "photo.on.rectangle",
                                color: .blue,
                                action: {} 
                            )
                            .overlay(
                                PhotosPicker(
                                    selection: $vm.headlessSelection,
                                    maxSelectionCount: 3,
                                    matching: .images
                                ) {
                                    Color.white.opacity(0.001) // Invisible tap target covering the card
                                }
                                .onChange(of: vm.headlessSelection) { _, newValue in
                                    vm.didSelectHeadless(newValue)
                                }
                            )
                            
                            MediaPickerNavCard(
                                title: "Custom Camera",
                                subtitle: "Raw viewfinder",
                                icon: "camera",
                                color: .blue
                            ) {
                                vm.flowState = .camera
                            }
                        }
                        
                        Divider().padding(.vertical, 8)
                        
                        Text("📚 Example Views")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        
                        // Tier 3: Full Custom Picker Example (isolated View + ViewModel)
                        MediaPickerNavCard(
                            title: "Tier 3 Example",
                            subtitle: "Build your own UI",
                            icon: "hammer.fill",
                            color: .orange
                        ) {
                            navigationManager.push { CustomPickerExampleView() }
                        }
                        
                        // Config Demo: All crop modes & multi-select
                        MediaPickerNavCard(
                            title: "Config Playground",
                            subtitle: "Engine settings",
                            icon: "slider.horizontal.3",
                            color: .orange,
                            action: {
                                navigationManager.push { MediaPickerDemoView() }
                            }
                        )
                        
                        MediaPickerNavCard(
                            title: "Custom Grid Demo",
                            subtitle: "Advanced styling",
                            icon: "square.grid.3x3.topleft.filled",
                            color: .green,
                            action: {
                                navigationManager.push { AdvancedPickerExampleView() }
                            }
                        )
                        
                        MediaPickerNavCard(
                            title: "Elite Picker B",
                            subtitle: "Full alternative UI",
                            icon: "star.fill",
                            color: .orange,
                            action: {
                                vm.showGeometricPicker = true
                            }
                        )
                    }
                }
                .padding(24)
            }
        }
        // 🧪 ELITE FLOW: Frictionless Modifier (Handles Selection -> Crop sequence)
        .mediaPicker(
            isPresented: $vm.showModifierPicker,
            configuration: .init(
                selectionLimit: 3,
                crop: .square,
                style: .tealSleek
            ),
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
        .fullScreenCover(isPresented: $vm.showGeometricPicker) {
            EliteGeometricPickerView(
                configuration: .init(selectionLimit: 5),
                onCompletion: { items in
                    vm.handlePickerResult(items)
                    vm.showGeometricPicker = false
                },
                onCancel: {
                    vm.showGeometricPicker = false
                }
            )
        }
    }
}
