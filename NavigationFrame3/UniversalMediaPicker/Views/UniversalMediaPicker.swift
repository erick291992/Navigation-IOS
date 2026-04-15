import SwiftUI
import PhotosUI

/// The main entry point for the Universal Media Picker (Crop Engine).
public struct UniversalMediaPicker: View {
    let configuration: MediaPickerConfiguration
    let onCompletion: ([MediaItem]) -> Void
    let onCancel: () -> Void
    let onGoBack: (() -> Void)? // Optional: Return to selection grid
    
    // View state
    @State private var containerSize: CGSize = .zero
    @State private var isProcessing: Bool = false
    @State private var viewModel: MediaPickerViewModel
    
    public init(
        configuration: MediaPickerConfiguration,
        initialItems: [MediaItem] = [],
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void,
        onGoBack: (() -> Void)? = nil
    ) {
        self.configuration = configuration
        self.onCompletion = onCompletion
        self.onCancel = onCancel
        self.onGoBack = onGoBack
        self._viewModel = State(initialValue: MediaPickerViewModel(
            configuration: configuration,
            initialItems: initialItems,
            onCompletion: onCompletion,
            onCancel: onCancel
        ))
    }
    
    public var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            
            switch viewModel.state.flowState {
            case .idle:
                // If items are already present, we should transition to processing
                // This is handled by the initial selection trigger in the parent/modifier
                Color.clear
                .onAppear {
                    // Logic to handle items if they were passed in (Headless mode)
                    if !viewModel.state.items.isEmpty && viewModel.state.flowState == .idle {
                        // Handled by VM logic usually
                    }
                }
                
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
                            Task {
                                let manager = MediaPickerManager.shared
                                do {
                                    let newItem = try await manager.process(croppedImage)
                                    await MainActor.run {
                                        viewModel.trigger(.didFinishCrop(item: newItem, index: index))
                                    }
                                }
                            }
                        },
                        onCancel: {
                            if let onGoBack = onGoBack {
                                onGoBack()
                            } else {
                                onCancel()
                            }
                        }
                    )
                    .id(index) // CRITICAL: Reset state for each index
                    .transition(.move(edge: .trailing))
                    .interactiveDismissDisabled()
                }
                
            case .finished:
                Color.clear
            }
        }
        .onAppear {
            // If items are passed to the VM (from Tier 3 or Headless), 
            // the VM should already have them in state.
        }
    }
}

private struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
                Text("Processing...")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
        }
    }
}
