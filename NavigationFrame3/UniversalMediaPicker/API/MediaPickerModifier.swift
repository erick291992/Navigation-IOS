import SwiftUI
import PhotosUI

// MARK: - Infrastructure Exception
//
// `MediaPickerModifier` is the picker module's entry-point ViewModifier and
// one of TWO documented places in the module that calls services directly
// from view code (the other being `CameraPreviewView`, the UIKit
// `UIViewRepresentable` bridge for the live camera feed). The strict
// View → ViewModel → Service rule documented in
// `DATA_FLOW_PATTERNS.md` (at the project root) does not apply here because:
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
// Every other file in the picker module follows the strict rule. For the
// full set of data-flow conventions (View → VM → Service, when to use
// `@Binding` vs callbacks, why VMs are `@MainActor` but workers are
// nonisolated, etc.), see `DATA_FLOW_PATTERNS.md` (at the project root).

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
                PickerPerfLog.event("modifier.onAppear → startWarming dispatched")
                Task { await CameraService.shared.startWarming() }
            }
            // Photo pre-fetch via `.task` because it IS async (we await
            // `prewarm()`) and the auto-cancellation on view disappear is a
            // nice bonus.
            .task {
                PickerPerfLog.event("modifier.task → prewarm awaited")
                // Awaiting (instead of calling the static `PhotoKitService.prewarm()`)
                // lets `.task`'s auto-cancellation propagate through the prewarm
                // pipeline if the host view disappears. App.init callers should
                // use the static `PhotoKitService.prewarm()` instead — they don't
                // have a view lifecycle to tie cancellation to. Both call the
                // same idempotent body; safe to use both in the same app.
                await PhotoKitService.shared.prewarm()
                PickerPerfLog.event("modifier.task → prewarm completed")
            }
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    PickerPerfLog.reset("sheet presenting")
                    // Cold-race protection: if the user tapped before the
                    // grid prewarm (step 4) finished, abort it now so its
                    // remaining requests don't compete with sheet-open's
                    // own PhotoKit traffic. No-op if prewarm already
                    // completed or never ran.
                    PhotoKitService.shared.cancelGridPrewarm()
                }
            }
            .sheet(isPresented: $isPresented, onDismiss: {
                // Per-session reset: clear the user's selection cache so the
                // next picker open starts with an empty selection. Goes
                // through `AssetGridViewModel.clearSession(for:)` rather than
                // touching the cache type directly — the view never sees the
                // cache implementation.
                AssetGridViewModel.clearSession(for: configuration.selectionLimit)
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
