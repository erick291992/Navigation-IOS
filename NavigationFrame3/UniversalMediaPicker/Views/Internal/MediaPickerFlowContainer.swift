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
            
            switch currentStage {
            case .select:
                UnifiedPickerView(
                    configuration: configuration,
                    onCompletion: { items in
                        self.selectedItems = items
                        withAnimation {
                            self.currentStage = .crop
                        }
                    },
                    onCancel: onCancel
                )
                .transition(.move(edge: .leading))
                
            case .crop:
                UniversalMediaPicker(
                    configuration: configuration,
                    initialItems: selectedItems,
                    onCompletion: onCompletion,
                    onCancel: onCancel,
                    onGoBack: {
                        withAnimation {
                            self.currentStage = .select
                        }
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
    }
}
