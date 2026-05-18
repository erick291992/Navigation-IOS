import SwiftUI

/// Self-contained camera viewfinder. Instantiates its own
/// `CameraViewfinderViewModel` internally. Takes `accentColor` as a styling
/// parameter (used by `PermissionNeededView` on the denied path).
///
/// The hybrid C mount strategy lives at `ViewfinderArea` — once mounted, this
/// view stays mounted (opacity-toggled by the parent) so returning to photo
/// mode is instant.
struct CameraViewfinderView: View {
    @State private var viewModel = CameraViewfinderViewModel()

    let accentColor: Color

    var body: some View {
        ZStack {
            if viewModel.isSourceReady {
                CameraPreviewView()
                if viewModel.showsLoadingSpinner {
                    ProgressView()
                        .tint(.white.opacity(0.7))
                }
            } else {
                PermissionNeededView(type: .camera, accentColor: accentColor)
            }
        }
        .task {
            await viewModel.warmUpIfNeeded()
        }
    }
}
