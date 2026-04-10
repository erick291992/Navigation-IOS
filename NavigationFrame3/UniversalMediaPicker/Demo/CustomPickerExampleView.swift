import SwiftUI
import PhotosUI

// MARK: - Tier 3 Example View
// This is a complete, self-contained example of building your OWN picker UI
// using the MediaPickerEngine. No Elite UI is used — you control everything.
//
// WHAT THIS DEMONSTRATES:
// 1. Your own gallery button design → pipes into Apple's PhotosPicker
// 2. Your own camera button design → pipes into CameraPicker
// 3. Engine processes the raw data → feeds into CropView for cropping
// 4. You get back finished [MediaItem] to use however you want

struct CustomPickerExampleView: View {
    @State private var vm = CustomPickerExampleViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                headerSection
                
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SECTION 1: Configuration
                // The developer picks crop mode & selection limit
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                configSection
                
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SECTION 2: Custom Trigger Buttons
                // YOUR design — the engine doesn't care what these look like
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                actionButtons
                
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SECTION 3: Results
                // Display the finished MediaItems however you want
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                if !vm.finishedItems.isEmpty {
                    resultsSection
                }
            }
            .padding(24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Custom Picker (Tier 3)")
        .navigationBarTitleDisplayMode(.large)
        
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // WIRING: CropView Sheet
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        .sheet(isPresented: isCroppingBinding) {
            cropSheet
        }
        
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // WIRING: Camera Full Screen
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        .fullScreenCover(isPresented: isCameraBinding) {
            CameraPicker(
                onCapture: { image in vm.didCapturePhoto(image) },
                onCancel: { vm.cancelFlow() }
            )
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Bindings for Sheet Presentation
    
    private var isCroppingBinding: Binding<Bool> {
        Binding(
            get: { if case .cropping = vm.flowState { return true } else { return false } },
            set: { if !$0 { vm.cancelFlow() } }
        )
    }
    
    private var isCameraBinding: Binding<Bool> {
        Binding(
            get: { if case .camera = vm.flowState { return true } else { return false } },
            set: { if !$0 { vm.cancelFlow() } }
        )
    }
    
    // MARK: - Sub Views (YOUR Custom Design)
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("Build Your Own Picker")
                .font(.title2.bold())
            
            Text("This view uses zero Elite UI.\nYou design everything — the engine handles the data.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }
    
    private var configSection: some View {
        VStack(spacing: 12) {
            Text("CONFIGURATION")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Crop mode picker
            Picker("Crop Mode", selection: $vm.cropMode) {
                Text("Square").tag(MediaCrop.square)
                Text("Portrait 4:5").tag(MediaCrop.portrait)
                Text("Landscape 16:9").tag(MediaCrop.landscape)
                Text("Circle").tag(MediaCrop.circle)
                Text("Freeform").tag(MediaCrop.freeform)
                Text("None").tag(MediaCrop.none)
            }
            .pickerStyle(.segmented)
            
            // Selection limit
            Stepper("Max Photos: \(vm.maxSelection)", value: $vm.maxSelection, in: 1...10)
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Text("YOUR CUSTOM BUTTONS")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                // ┌─────────────────────────────────────────┐
                // │ Gallery Button — wraps Apple PhotosPicker │
                // │ Design this however you want              │
                // └─────────────────────────────────────────┘
                PhotosPicker(
                    selection: $vm.photosSelection,
                    maxSelectionCount: vm.maxSelection,
                    matching: .images
                ) {
                    customButton(
                        title: "Gallery",
                        icon: "photo.on.rectangle",
                        color: .blue
                    )
                }
                .buttonStyle(.plain)
                .onChange(of: vm.photosSelection) { _, newValue in
                    vm.didSelectPhotos(newValue)
                }
                
                // ┌─────────────────────────────────────────┐
                // │ Camera Button — opens CameraPicker        │
                // │ Design this however you want              │
                // └─────────────────────────────────────────┘
                Button {
                    vm.flowState = .camera
                } label: {
                    customButton(
                        title: "Camera",
                        icon: "camera.fill",
                        color: .green
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RESULTS (\(vm.finishedItems.count))")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Clear") {
                    vm.finishedItems = []
                }
                .font(.caption.bold())
                .foregroundColor(.red)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vm.finishedItems) { item in
                        Image(uiImage: item.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
    
    // MARK: - Crop Sheet (The ONE thing you use from the library)
    
    @ViewBuilder
    private var cropSheet: some View {
        if case .cropping(let index, let total) = vm.flowState,
           index < vm.itemsToCrop.count {
            let item = vm.itemsToCrop[index]
            CropView(
                item: item,
                crop: vm.cropMode,
                subtitle: total > 1 ? "\(index + 1) of \(total)" : nil,
                thumbnails: total > 1 ? vm.itemsToCrop.map { $0.thumbnail } : nil,
                activeIndex: total > 1 ? index : nil,
                croppedIndices: vm.croppedResults.isEmpty ? [] : Set(vm.croppedResults.keys),
                onJump: total > 1 ? { vm.jumpToCropIndex($0) } : nil,
                onDone: { croppedImage in
                    vm.didFinishCrop(croppedImage, at: index)
                },
                onCancel: {
                    vm.cancelFlow()
                }
            )
            .id(index) // Force reset when jumping between images
        }
    }
    
    // MARK: - Reusable Custom Button (YOUR design)
    
    private func customButton(title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    CustomPickerExampleView()
}
