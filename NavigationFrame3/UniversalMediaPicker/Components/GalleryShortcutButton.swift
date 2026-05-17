import SwiftUI
import Photos
import PhotosUI

/// 48x48 gallery shortcut button at the bottom-left of the shutter row.
/// Pure presentational view — takes a pre-resolved `image: UIImage?` and
/// the current `authStatus`; the tap target shape depends on auth state:
///
/// - `.authorized` → SwiftUI `PhotosPicker` (native; no UIKit bridge,
///   no delegate, no topVC traversal — Apple handles presentation).
/// - `.limited` / `.denied` / `.restricted` → `Button` calling
///   `onLimitedOrDeniedTap` so the parent VM can route to either the
///   limited-access library picker (no SwiftUI equivalent) or the
///   Settings deeplink.
/// - `.notDetermined` → disabled placeholder; onboarding handles auth.
///
/// The image itself is loaded by `PickerViewModel.loadGalleryThumbIfNeeded()`
/// and passed down through `ShutterAndModeBarView`. This view never touches
/// PhotoKit or `ThumbnailCache`.
struct GalleryShortcutButton: View {
    let authStatus: PHAuthorizationStatus
    let image: UIImage?
    let selectionLimit: Int
    @Binding var pickerSelection: [PhotosPickerItem]
    /// Fires for limited, denied, restricted. Authorized uses PhotosPicker.
    let onLimitedOrDeniedTap: () -> Void

    var body: some View {
        if authStatus == .authorized {
            PhotosPicker(
                selection: $pickerSelection,
                maxSelectionCount: selectionLimit,
                matching: .images
            ) {
                buttonContent
            }
            .buttonStyle(.plain)
        } else {
            Button(action: {
                // TODO: restore haptic feedback once Core Haptics pre-warm
                // is solved without re-introducing the first-tap stall.
                // Same root cause as the cell + previewer-tap TODOs.
                onLimitedOrDeniedTap()
            }) {
                buttonContent
            }
            .disabled(authStatus == .notDetermined)
        }
    }

    /// The four-state visual: thumbnail / spinner / lock / placeholder.
    /// Same content rendered regardless of whether the wrapper is a
    /// `PhotosPicker` or a `Button`.
    @ViewBuilder
    private var buttonContent: some View {
        ZStack {
            if (authStatus == .authorized || authStatus == .limited), let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .cornerRadius(10)
                    .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.6), lineWidth: 2)
                    )
                    .allowsHitTesting(false)
            } else if authStatus == .denied || authStatus == .restricted {
                deniedState
            } else if authStatus == .authorized || authStatus == .limited {
                loadingState
            } else {
                placeholderState
            }
        }
    }

    private var deniedState: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.1))
            .frame(width: 48, height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3), lineWidth: 2)
            )
            .overlay(Image(systemName: "lock.fill").foregroundColor(.white.opacity(0.4)))
    }

    /// Authorized but the parent hasn't resolved the gallery thumbnail yet
    /// (or the library has no photos). Small spinner so the user knows
    /// this square is loading, not empty. Flips to the thumbnail the
    /// moment `image` becomes non-nil via the @Observable cascade from
    /// `PickerViewModel.galleryThumbImage`.
    private var loadingState: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.1))
            .frame(width: 48, height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3), lineWidth: 2)
            )
            .overlay(ProgressView().tint(.white.opacity(0.5)))
    }

    private var placeholderState: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.1))
            .frame(width: 48, height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3), lineWidth: 2)
            )
            .overlay(Image(systemName: "photo").foregroundColor(.white.opacity(0.4)))
    }
}
