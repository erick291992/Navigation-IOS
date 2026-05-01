import SwiftUI

/// A container that manages the transition between selection and cropping within a single sheet.
/// This prevents the "Double Sheet" flickering issue and provides elite performance.
struct MediaPickerFlowContainer: View {
    let configuration: MediaPickerConfiguration
    let onCompletion: ([MediaItem]) -> Void
    let onCancel: () -> Void
    
    @State private var currentStage: FlowStage = .select
    @State private var selectedItems: [MediaItem] = []
    
    enum FlowStage {
        case select
        case crop
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 1. Base Layer (Always alive to preserve selection & scroll state)
            UnifiedCreatorView(
                configuration: configuration,
                onCompletion: { items in
                    self.selectedItems = items
                    withAnimation {
                        self.currentStage = .crop
                    }
                },
                onCancel: onCancel
            )
            // Optional optimization: hide layer accessibility when covered
            .accessibilityHidden(currentStage == .crop)
            
            // 2. Crop Layer (Pushed on top, destroyed when dismissed to ensure fresh state next time)
            if currentStage == .crop {
                CropFlowView(
                    configuration: configuration,
                    initialItems: selectedItems,
                    onCompletion: onCompletion,
                    onCancel: onCancel,
                    onGoBack: {
                        withAnimation {
                            self.currentStage = .select
                            self.selectedItems = [] // Clear so next trip is fresh
                        }
                    }
                )
                .transition(.move(edge: .trailing))
                .zIndex(1) // Ensure it always animates on top
            }
        }
    }
}
