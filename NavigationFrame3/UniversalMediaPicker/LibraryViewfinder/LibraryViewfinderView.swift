import SwiftUI
import Photos

/// Self-contained library viewfinder. Instantiates its own
/// `LibraryViewfinderViewModel` internally. Receives `previewAsset` as a
/// `let` parameter from the parent (TextField-style primitive pattern) so
/// grid-tap → top-viewfinder updates flow through `PickerViewModel`.
///
/// Renders one of four states based on auth + data:
/// 1. `.denied` / `.restricted` → `PermissionNeededView`.
/// 2. Authorized, fetch in flight → `ProgressView`.
/// 3. Authorized, fetch done, no assets → `EmptyStateView` with "Open Library".
/// 4. Authorized, has assets → `LibraryPreviewer` showing the chosen asset.
struct LibraryViewfinderView: View {
    @State private var viewModel = LibraryViewfinderViewModel()

    let previewAsset: PHAsset?
    let accentColor: Color
    /// Fires when the user wants to present the system picker (tap on the
    /// preview or on the empty-state "Open Library" button in
    /// non-`.limited` mode). Parent routes to `PhotoKitService.openSystemPicker`
    /// with its own completion handler.
    let onOpenSystemPicker: () -> Void

    var body: some View {
        Group {
            if viewModel.authStatus == .denied || viewModel.authStatus == .restricted {
                PermissionNeededView(type: .library, accentColor: accentColor)
            } else if viewModel.isLoadingRecents {
                ProgressView()
                    .tint(.white.opacity(0.7))
            } else if !viewModel.hasRecents {
                EmptyStateView(
                    icon: "photo.on.rectangle",
                    title: "No Recent Photos Found",
                    actionTitle: "Open Library",
                    onAction: {
                        if viewModel.authStatus == .limited {
                            viewModel.openLimitedPicker()
                        } else {
                            onOpenSystemPicker()
                        }
                    }
                )
            } else {
                let displayedAsset = viewModel.displayAsset(preferring: previewAsset)
                LibraryPreviewer(
                    assetID: displayedAsset?.localIdentifier,
                    initialImage: viewModel.thumbnail(for: displayedAsset),
                    loadAsync: displayedAsset.map { asset in
                        { await viewModel.requestThumbnail(for: asset) }
                    }
                )
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onOpenSystemPicker()
                }
            }
        }
        .task {
            await viewModel.loadRecentsIfNeeded()
        }
    }
}
