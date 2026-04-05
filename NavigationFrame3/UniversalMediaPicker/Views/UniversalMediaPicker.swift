import SwiftUI
import PhotosUI

/// The main entry point for the Universal Media Picker.
public struct UniversalMediaPicker: View {
    let configuration: MediaPickerConfiguration
    let onCompletion: ([MediaItem]) -> Void
    let onCancel: () -> Void
    
    @State private var viewModel: MediaPickerViewModel
    @State private var selection: [PhotosPickerItem] = []
    
    public init(
        configuration: MediaPickerConfiguration,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onCompletion = onCompletion
        self.onCancel = onCancel
        self._viewModel = State(initialValue: MediaPickerViewModel(
            configuration: configuration,
            onCompletion: onCompletion,
            onCancel: onCancel
        ))
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                switch viewModel.state.flowState {
                case .idle:
                    SelectionStage(
                        viewModel: viewModel,
                        selection: $selection,
                        configuration: configuration
                    )
                    
                case .processing:
                    ProcessingOverlay()
                    
                case .camera:
                    CameraPicker(
                        onCapture: { image in
                            viewModel.trigger(.didCapture(image))
                        },
                        onCancel: {
                            viewModel.trigger(.didCancelCrop)
                        }
                    )
                    .ignoresSafeArea()
                    
                case .cropping(let index, let total):
                    if index < viewModel.state.items.count {
                        let item = viewModel.state.items[index]
                        CropView(
                            item: item,
                            crop: configuration.crop,
                            style: configuration.style,
                            subtitle: "\(index + 1) of \(total)",
                            thumbnails: viewModel.state.items.map { $0.thumbnail },
                            activeIndex: index,
                            croppedIndices: Set(viewModel.state.croppedResults.keys),
                            onJump: { targetIndex in
                                viewModel.jumpTo(index: targetIndex)
                            },
                            onDone: { croppedImage in
                                // Process cropped image back into a MediaItem
                                Task {
                                    let manager = MediaPickerManager.shared
                                    do {
                                        let newItem = try await manager.process(croppedImage)
                                        await MainActor.run {
                                            viewModel.trigger(.didFinishCrop(newItem))
                                        }
                                    }
                                }
                            },
                            onCancel: {
                                viewModel.trigger(.didCancelCrop)
                            }
                        )
                        .transition(.move(edge: .trailing))
                        .interactiveDismissDisabled()
                    }
                    
                case .finished:
                    // Finished is handled by onCompletion in ViewModel, 
                    // which resets state back to .idle
                    Color.clear
                        .onAppear {
                            // This might not be needed if finalization is triggered in VM
                        }
                }
            }
            .navigationTitle("Select Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if case .idle = viewModel.state.flowState {
                        Button("Cancel") {
                            viewModel.cancel()
                        }
                    }
                }
            }
            .onChange(of: selection) { _, newValue in
                guard !newValue.isEmpty else { return }
                viewModel.trigger(.didSelect(newValue))
                selection = [] // Clear immediately for next selection
            }
            .onAppear {
                selection = []
            }
        }
    }
}

// MARK: - Subviews

private struct SelectionStage: View {
    var viewModel: MediaPickerViewModel
    @Binding var selection: [PhotosPickerItem]
    let configuration: MediaPickerConfiguration
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                // Photo Library Card
                PhotosPickerView(
                    selection: $selection,
                    limit: configuration.selectionLimit,
                    filter: configuration.allowedTypes,
                    style: configuration.style
                )
                
                // Camera Card
                if configuration.showCamera {
                    Button(action: { viewModel.trigger(.requestCamera) }) {
                        HStack(spacing: 16) {
                            // Icon in a circle
                            ZStack {
                                Circle()
                                    .fill(configuration.style.accentColor.opacity(0.1))
                                    .frame(width: 54, height: 54)
                                
                                configuration.style.cameraIcon
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(configuration.style.accentColor)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(configuration.style.cameraLabel)
                                    .font(configuration.style.font.weight(.semibold))
                                    .foregroundColor(.primary)
                                
                                Text(configuration.style.cameraSubtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color(.systemBackground))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
                    }
                }
                
                if let error = viewModel.state.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            Spacer() // Double spacer at bottom for "Instagram" lift
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

private struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView("Processing...")
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        }
    }
}
