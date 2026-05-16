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
            // Camera pre-warm via .onAppear (NOT .task) because .onAppear fires
            // synchronously when the host view is added to the hierarchy, while
            // .task has ~16-32ms of additional scheduling overhead. For a
            // latency-critical wake-up like AVCaptureSession.startRunning, every
            // millisecond of head-start matters — the camera session is the
            // dominant cost in the cold-start tap-to-grid path.
            //
            // We deliberately keep this inside the picker module rather than
            // exposing it to consumers. The picker's public API is just
            // `.mediaPicker(isPresented:configuration:onCompletion:)` —
            // consumers should not have to know about CameraService /
            // PhotoKitService internals to get a snappy picker.
            // Camera pre-warm via .onAppear (NOT .task) because .onAppear fires
            // synchronously when the host view is added to the hierarchy, while
            // .task has ~16-32ms of additional scheduling overhead. For the
            // latency-critical AVCaptureSession.startRunning, every millisecond
            // of head-start matters — camera-session cold start is the dominant
            // cost in the tap-to-grid path.
            //
            // Both pre-warms are kept INSIDE the picker module — consumers only
            // need `.mediaPicker(isPresented:configuration:onCompletion:)` and
            // shouldn't have to know about CameraService / PhotoKitService.
            .onAppear {
                // CameraService.shared.setup() is idempotent (the
                // `guard session.inputs.isEmpty` inside returns early on the
                // second call) so this is safe to fire on every appearance.
                CameraService.shared.setup()
            }
            // Photo pre-fetch via .task because it IS async (we await
            // fetchRecentAssets) and the auto-cancellation on view disappear is
            // a nice bonus.
            .task {
                // Pre-fetch recent assets ONLY if permission is already granted.
                // Do NOT trigger the iOS permission prompt eagerly here — that
                // would surprise the user before they've intent-tapped the
                // picker. First-time users will hit the prompt at tap time.
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                guard status == .authorized || status == .limited else { return }
                await PhotoKitService.shared.fetchRecentAssets()

                // Also pre-warm the shared AssetGridViewModel cache (used by
                // the grid in the bottom panel). PhotoKitService.recentAssets
                // and AssetGridViewModel.state.assets are SEPARATE data stores —
                // the former feeds the viewfinder / gallery-shortcut, the latter
                // feeds the actual LazyVGrid. Warming both means that when the
                // user taps to open the picker, both surfaces have data ready
                // and neither needs to do an on-appear load.
                let gridVM = AssetGridViewModel.shared(selectionLimit: configuration.selectionLimit)
                if gridVM.state.assets.isEmpty {
                    gridVM.trigger(.loadInitialData)
                }
            }
            .sheet(isPresented: $isPresented, onDismiss: {
                // Per-session reset for the shared AssetGridViewModel cache.
                // The grid VM is process-cached (see AssetGridViewModel.shared),
                // so its loaded asset list survives upstream identity churn that
                // was causing the popup-dismiss flicker. The flip side is that
                // selection state would leak into the next picker open; clear it
                // here when the sheet truly goes away.
                AssetGridViewModel.shared(selectionLimit: configuration.selectionLimit)
                    .prepareForNewSession()
            }) {
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
