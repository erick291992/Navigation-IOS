import SwiftUI
import Photos
import PhotosUI

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
///
/// The previewer's tap target is `PhotosPicker` when authorized (SwiftUI
/// native — no UIKit bridge, no delegate, no topVC traversal) and a
/// `Button` when limited (the limited-access library picker has no SwiftUI
/// equivalent and must use the UIKit bridge in `PhotoKitService`).
struct LibraryViewfinderView: View {
    @State private var viewModel = LibraryViewfinderViewModel()

    let previewAsset: PHAsset?
    let accentColor: Color
    let selectionLimit: Int
    @Binding var pickerSelection: [PhotosPickerItem]
    /// Limited-access path — opens `PHPhotoLibrary.presentLimitedLibraryPicker`
    /// via the parent's VM. No SwiftUI equivalent exists for this UI.
    let onLimitedTap: () -> Void
    /// Empty-state fallback when authorized — `EmptyStateView`'s internal
    /// Button can't cleanly host a `PhotosPicker` without refactoring the
    /// component, so we still route through the parent's imperative
    /// `openSystemPicker()` for that specific edge case.
    let onAuthorizedEmptyStateFallback: () -> Void

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
                            onLimitedTap()
                        } else {
                            onAuthorizedEmptyStateFallback()
                        }
                    }
                )
            } else {
                let displayedAsset = viewModel.displayAsset(preferring: previewAsset)
                let previewer = LibraryPreviewer(
                    assetID: displayedAsset?.localIdentifier,
                    initialImage: viewModel.thumbnail(for: displayedAsset),
                    loadAsync: displayedAsset.map { asset in
                        { await viewModel.requestThumbnail(for: asset) }
                    }
                )

                if viewModel.authStatus == .limited {
                    previewer.onTapGesture {
                        // TODO: restore haptic feedback once Core Haptics
                        // pre-warm is solved without re-introducing the
                        // first-tap stall (see AssetGridView cell TODO).
                        onLimitedTap()
                    }
                } else if viewModel.authStatus == .authorized {
                    PhotosPicker(
                        selection: $pickerSelection,
                        maxSelectionCount: selectionLimit,
                        matching: .images
                    ) {
                        previewer
                    }
                    .buttonStyle(.plain)
                } else {
                    // notDetermined etc — render previewer without a tap
                    // action. (Onboarding flow handles permission request
                    // elsewhere.)
                    previewer
                }
            }
        }
        .task {
            await viewModel.loadRecentsIfNeeded()
        }
    }
}
