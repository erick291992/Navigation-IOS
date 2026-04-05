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
            .sheet(isPresented: $isPresented) {
                MediaPickerFlowContainer(
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
                .ignoresSafeArea()
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
