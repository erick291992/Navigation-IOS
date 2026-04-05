import SwiftUI

public struct MediaPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let configuration: MediaPickerConfiguration
    let onCompletion: ([MediaItem]) -> Void
    let onCancel: () -> Void
    
    // Internal ID to force state reset on each presentation
    @State private var pickerId = UUID()
    
    public func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: {
                pickerId = UUID() // Reset for next time
            }) {
                UniversalMediaPicker(
                    configuration: configuration,
                    onCompletion: { items in
                        onCompletion(items)
                        isPresented = false
                    },
                    onCancel: {
                        onCancel()
                        isPresented = false
                    }
                )
                .id(pickerId)
            }
    }
}

public extension View {
    /// A convenient one-liner to present the UniversalMediaPicker.
    /// - Parameters:
    ///   - isPresented: Binding to show/hide the picker.
    ///   - configuration: Configuration (crop mode, limit, style, etc).
    ///   - onCompletion: Closure called with selected and processed MediaItems.
    ///   - onCancel: Optional closure called when the user cancels.
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
