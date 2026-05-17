import SwiftUI
import Photos

/// 48x48 gallery shortcut button at the bottom-left of the shutter row.
/// Pure presentational view — takes a pre-resolved `image: UIImage?` and
/// the current `authStatus`; renders one of four states:
/// 1. Authorized/limited + image → thumbnail, tappable.
/// 2. Authorized/limited + nil image → loading spinner inside frame.
///    Covers both "recents still loading" and "no photos in the library."
/// 3. Denied/restricted → lock icon, tappable (opens Settings via callback).
/// 4. Other (notDetermined) → generic photo icon, disabled.
///
/// The image is loaded by `PickerViewModel.loadGalleryThumbIfNeeded()`
/// and passed down through `ShutterAndModeBarView`. This view never
/// touches PhotoKit or `ThumbnailCache`.
struct GalleryShortcutButton: View {
    let authStatus: PHAuthorizationStatus
    let image: UIImage?
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            // TODO: restore haptic feedback once Core Haptics pre-warm is
            // solved without re-introducing the first-tap stall. Same root
            // cause as AssetGridView's cell-tap TODO — first
            // `UIImpactFeedbackGenerator(...).impactOccurred()` of a session
            // cold-starts the Core Haptics engine and blocks main ~400-1000ms,
            // which makes this 48x48 button visually stuck "pressed" until
            // the system picker finally presents. Removed to match the cell
            // decision; restore together when a measured prewarm exists.
            onTap()
        }) {
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
        .disabled(authStatus == .notDetermined)
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
