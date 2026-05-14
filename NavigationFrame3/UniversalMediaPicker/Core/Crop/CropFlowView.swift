import SwiftUI
import PhotosUI

/// The orchestrator for the multi-item cropping flow.
public struct CropFlowView: View {
    let configuration: MediaPickerConfiguration
    let onCompletion: ([MediaItem]) -> Void
    let onCancel: () -> Void
    let onGoBack: (() -> Void)?
    
    @State private var viewModel: CropFlowViewModel
    
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
        self._viewModel = State(initialValue: CropFlowViewModel(
            configuration: configuration,
            initialItems: initialItems,
            onCompletion: onCompletion,
            onCancel: onCancel
        ))
    }
    
    public var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            
            switch viewModel.flowState {
            case .idle:
                Color.clear
                
            case .processing:
                ProcessingOverlay()
                
            case .camera:
                CameraPicker(
                    onCapture: { image in
                        viewModel.handleCapture(image)
                    },
                    onCancel: {
                        viewModel.cancelCrop()
                    }
                )
                .ignoresSafeArea()
                
            case .cropping(let index, let total):
                if index < viewModel.items.count {
                    let item = viewModel.items[index]
                    CropView(
                        item: item,
                        crop: configuration.crop,
                        style: configuration.style,
                        subtitle: "\(index + 1) of \(total)",
                        thumbnails: viewModel.items.map { $0.thumbnail },
                        activeIndex: index,
                        croppedIndices: Set(viewModel.croppedResults.keys),
                        onJump: { targetIndex in
                            viewModel.jumpTo(index: targetIndex)
                        },
                        onDone: { croppedImage in
                            // Create MediaItem directly — do NOT re-process through
                            // manager.process() which would run generateThumbnail()
                            // and destroy the crop's aspect ratio by squaring it.
                            let data = croppedImage.jpegData(compressionQuality: 0.9) ?? Data()
                            let croppedItem = MediaItem(
                                data: data,
                                thumbnail: croppedImage,
                                contentType: item.contentType,
                                originalURL: item.originalURL
                            )
                            viewModel.finishCrop(item: croppedItem, index: index)
                        },
                        onCancel: {
                            if let onGoBack = onGoBack {
                                onGoBack()
                            } else {
                                onCancel()
                            }
                        }
                    )
                    .id(index)
                    .transition(.move(edge: .trailing))
                    .interactiveDismissDisabled()
                }
                
            case .finished:
                Color.clear
            }
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
