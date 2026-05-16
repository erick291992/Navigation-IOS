import SwiftUI
import Photos

/// Dumb layout container for the top-half viewfinder. **No ViewModel.**
///
/// Switches between the three viewfinder subviews per `mode` using the
/// **hybrid C mount strategy**: `CameraViewfinderView` mounts once on first
/// photo-mode entry and stays mounted thereafter (opacity-toggled per mode),
/// so returning to photo mode is instant — no UIKit re-bridging cost.
/// `LibraryViewfinderView` and `HistoryViewfinderView` mount/unmount with
/// their mode because they're cheap.
///
/// All cross-cutting state (`previewAsset`, `previewHistoryItem`, `history`)
/// flows in as `let` parameters from `PickerView` (TextField-style).
struct ViewfinderArea: View {
    let mode: PickerMode
    let previewAsset: PHAsset?
    let previewHistoryItem: MediaItem?
    let history: [MediaItem]
    let accentColor: Color
    let onOpenSystemPicker: () -> Void

    /// Tracks whether the camera has been shown at least once during this
    /// picker session. Once set, the camera viewfinder stays mounted so the
    /// AVCaptureSession warm cost (~50ms UIKit bridging) is paid only once.
    @State private var hasMountedCamera = false

    var body: some View {
        ZStack {
            if hasMountedCamera || mode == .photo {
                CameraViewfinderView(accentColor: accentColor)
                    .opacity(mode == .photo ? 1 : 0)
            }

            if mode == .library {
                LibraryViewfinderView(
                    previewAsset: previewAsset,
                    accentColor: accentColor,
                    onOpenSystemPicker: onOpenSystemPicker
                )
            }

            if mode == .reuse {
                HistoryViewfinderView(
                    history: history,
                    previewItem: previewHistoryItem
                )
            }
        }
        .onChange(of: mode, initial: true) { _, newMode in
            if newMode == .photo { hasMountedCamera = true }
        }
    }
}
