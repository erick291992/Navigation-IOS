import SwiftUI
import PhotosUI

public struct MediaPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let configuration: MediaPickerConfiguration
    let onCompletion: ([MediaItem]) -> Void
    let onCancel: () -> Void
    
    // Internal States for Sequential Flow
    @State private var isSystemPickerPresented = false
    @State private var isCropEnginePresented = false
    @State private var selection: [PhotosPickerItem] = []
    
    // Internal ID to force state reset
    @State private var pickerId = UUID()
    
    public func body(content: Content) -> some View {
        content
            // Stage 1: The System Picker (Triggered immediately on parent)
            .photosPicker(
                isPresented: $isSystemPickerPresented,
                selection: $selection,
                maxSelectionCount: configuration.selectionLimit,
                matching: configuration.allowedTypes.isEmpty ? .images : .any(of: configuration.allowedTypes)
            )
            // Stage 2: The Crop Engine (Presented after picker dismisses)
            .sheet(isPresented: $isCropEnginePresented, onDismiss: {
                // If we are not transitioning back to picker, reset the whole flow
                if !isSystemPickerPresented {
                    pickerId = UUID()
                    isPresented = false
                }
            }) {
                UniversalMediaPicker(
                    configuration: configuration,
                    onCompletion: { items in
                        onCompletion(items)
                        isCropEnginePresented = false
                        isPresented = false
                    },
                    onCancel: {
                        onCancel()
                        isCropEnginePresented = false
                        isPresented = false
                    },
                    onGoBack: {
                        // User wants to return to selection grid (Instagram-style)
                        isCropEnginePresented = false
                        
                        // Re-trigger stage 1 after transition completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            selection = [] // Clear previous selection for fresh start
                            isSystemPickerPresented = true
                        }
                    }
                )
                .id(pickerId)
            }
            // Logic Bridge: Transition from select -> crop
            .onChange(of: isPresented) { _, presented in
                if presented {
                    isSystemPickerPresented = true
                }
            }
            .onChange(of: isSystemPickerPresented) { _, presented in
                // Handle cancellation of system picker
                if !presented && selection.isEmpty && !isCropEnginePresented {
                    isPresented = false
                    onCancel()
                }
            }
            .onChange(of: selection) { _, newValue in
                guard !newValue.isEmpty else { return }
                // Selection made! Switch to Crop Stage
                isSystemPickerPresented = false
                
                // Small delay to let system picker dismiss cleanly (Apple aesthetic)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isCropEnginePresented = true
                }
            }
    }
}

public extension View {
    func mediaPicker(
        isPresented: Binding<Bool>,
        configuration: MediaPickerConfiguration = .init(),
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        self.modifier(MediaPickerModifier(
            isPresented: isPresented,
            configuration: configuration,
            onCompletion: onCompletion,
            onCancel: onCancel
        ))
    }
}
