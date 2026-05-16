import SwiftUI
import PhotosUI

// MARK: - Infrastructure Exception
//
// `MediaPickerModifier` is the picker module's entry-point ViewModifier. It
// is the ONLY place in the picker module that calls services directly from
// view code. The strict View → ViewModel → Service rule (see Coding
// Conventions §1.7 of the rebuild plan) does not apply here because:
//
// 1. The modifier fires BEFORE any picker ViewModel exists. The
//    `PickerViewModel` is constructed inside the sheet's content closure when
//    the sheet presents — at the time `.onAppear` and `.task` fire on the
//    host view, there is no VM to route through.
// 2. The prewarm IS the value the modifier provides. Routing it through a
//    "PrewarmService" would just add a file that delegates to two other
//    services without eliminating the rule violation; the violation would
//    just move to a smaller surface. We accept the exception here and
//    document it explicitly.
//
// Every other file in the picker module follows the strict rule.

public struct MediaPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let configuration: MediaPickerConfiguration
    let onCompletion: ([MediaItem]) -> Void
    let onCancel: () -> Void

    public func body(content: Content) -> some View {
        content
            // Camera pre-warm via `.onAppear` (NOT `.task`) because
            // `.onAppear` fires synchronously when the host view is added to
            // the hierarchy, while `.task` has ~16-32ms of additional
            // scheduling overhead. For a latency-critical wake-up like
            // `AVCaptureSession.startRunning`, every millisecond of head-start
            // matters — camera-session cold-start dominates the tap-to-grid path.
            //
            // `startWarming()` is async; we kick it off in a Task inside
            // `.onAppear` so the call site stays synchronous and fires immediately.
            // `startWarming()` is idempotent (early-returns if the session is
            // already configured) so this is safe to fire on every appearance.
            .onAppear {
                Task { await CameraService.shared.startWarming() }
            }
            // Photo pre-fetch via `.task` because it IS async (we await
            // `prewarm()`) and the auto-cancellation on view disappear is a
            // nice bonus.
            .task {
                // `prewarm()` internally checks authorization status and
                // early-returns if not granted — first-time users hit the
                // prompt at their intent moment, not eagerly here.
                await PhotoKitService.shared.prewarm()

                // Also warm the shared `AssetGridViewModel` cache (used by
                // the grid in the bottom panel). `PhotoKitService.recentAssets`
                // and `AssetGridViewModel.state.assets` are SEPARATE data
                // stores — the former feeds the viewfinder + gallery-shortcut,
                // the latter feeds the actual LazyVGrid. Warming both means
                // that when the user taps to open the picker, both surfaces
                // have data ready and neither needs to do an on-appear load.
                let gridViewModel = AssetGridViewModel.shared(selectionLimit: configuration.selectionLimit)
                if gridViewModel.state.assets.isEmpty {
                    gridViewModel.trigger(.loadInitialData)
                }
            }
            .sheet(isPresented: $isPresented, onDismiss: {
                // Per-session reset for the shared `AssetGridViewModel` cache.
                // The grid VM is process-cached (see `AssetGridViewModel.shared(selectionLimit:)`),
                // so its loaded asset list survives upstream identity churn
                // that was causing the popup-dismiss flicker. The flip side is
                // that selection state would leak into the next picker open;
                // clear it here when the sheet truly goes away.
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
