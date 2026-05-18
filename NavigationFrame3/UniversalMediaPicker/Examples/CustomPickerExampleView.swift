import SwiftUI
import PhotosUI

// MARK: - Custom Picker Example
// A complete, self-contained example of building your OWN picker UI using
// `MediaPickerManager`. No Elite UI is used — you control everything.
//
// WHAT THIS DEMONSTRATES:
// 1. Your own gallery button design → pipes into Apple's PhotosPicker
// 2. Your own camera button design → pipes into CameraPicker
// 3. MediaPickerManager processes the raw data → feeds into CropView for cropping
// 4. You get back finished [MediaItem] to use however you want

struct CustomPickerExampleView: View {
    @State private var viewModel = CustomPickerExampleViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                configSection      // crop mode + selection limit
                actionButtons      // gallery + camera triggers (consumer's own design)
                if !viewModel.finishedItems.isEmpty {
                    resultsSection
                }
            }
            .padding(24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Custom Picker (Tier 3)")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: isCroppingBinding) {
            cropSheet
        }
        .fullScreenCover(isPresented: isCameraBinding) {
            CameraPicker(
                onCapture: { image in viewModel.didCapturePhoto(image) },
                onCancel: { viewModel.cancelFlow() }
            )
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Bindings for Sheet Presentation
    
    private var isCroppingBinding: Binding<Bool> {
        Binding(
            get: { if case .cropping = viewModel.flowState { return true } else { return false } },
            set: { if !$0 { viewModel.cancelFlow() } }
        )
    }
    
    private var isCameraBinding: Binding<Bool> {
        Binding(
            get: { if case .camera = viewModel.flowState { return true } else { return false } },
            set: { if !$0 { viewModel.cancelFlow() } }
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
            Picker("Crop Mode", selection: $viewModel.cropMode) {
                Text("Square").tag(MediaCrop.square)
                Text("Portrait 4:5").tag(MediaCrop.portrait)
                Text("Landscape 16:9").tag(MediaCrop.landscape)
                Text("Circle").tag(MediaCrop.circle)
                Text("Freeform").tag(MediaCrop.freeform)
                Text("None").tag(MediaCrop.none)
            }
            .pickerStyle(.segmented)
            
            // Selection limit
            Stepper("Max Photos: \(viewModel.maxSelection)", value: $viewModel.maxSelection, in: 1...10)
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
                // Gallery button — wraps Apple's PhotosPicker.
                PhotosPicker(
                    selection: $viewModel.photosSelection,
                    maxSelectionCount: viewModel.maxSelection,
                    matching: .images
                ) {
                    customButton(
                        title: "Gallery",
                        icon: "photo.on.rectangle",
                        color: .blue
                    )
                }
                .buttonStyle(.plain)
                .onChange(of: viewModel.photosSelection) { _, newValue in
                    viewModel.didSelectPhotos(newValue)
                }
                
                // Camera button — opens the UIKit-bridged CameraPicker.
                Button {
                    viewModel.flowState = .camera
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
                Text("RESULTS (\(viewModel.finishedItems.count))")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Clear") {
                    viewModel.finishedItems = []
                }
                .font(.caption.bold())
                .foregroundColor(.red)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.finishedItems) { item in
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
        if case .cropping(let index, let total) = viewModel.flowState,
           index < viewModel.itemsToCrop.count {
            let item = viewModel.itemsToCrop[index]
            CropView(
                item: item,
                crop: viewModel.cropMode,
                subtitle: total > 1 ? "\(index + 1) of \(total)" : nil,
                thumbnails: total > 1 ? viewModel.itemsToCrop.map { $0.thumbnail } : nil,
                activeIndex: total > 1 ? index : nil,
                croppedIndices: viewModel.croppedResults.isEmpty ? [] : Set(viewModel.croppedResults.keys),
                onJump: total > 1 ? { viewModel.jumpToCropIndex($0) } : nil,
                onDone: { croppedImage in
                    viewModel.didFinishCrop(croppedImage, at: index)
                },
                onCancel: {
                    viewModel.cancelFlow()
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
