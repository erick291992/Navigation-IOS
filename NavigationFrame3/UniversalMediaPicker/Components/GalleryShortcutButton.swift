import SwiftUI
import Photos

/// 48x48 gallery shortcut button at the bottom-left of the shutter row.
/// Renders one of four states based on `authStatus` + the presence of a
/// `firstAsset`:
/// 1. Authorized/limited + asset → thumbnail of the asset, tappable.
/// 2. Authorized/limited + no asset → loading spinner inside frame.
/// 3. Denied/restricted → lock icon, tappable (opens Settings via callback).
/// 4. Other (notDetermined) → generic photo icon, disabled.
struct GalleryShortcutButton: View {
    let authStatus: PHAuthorizationStatus
    let firstAsset: PHAsset?
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            ZStack {
                if (authStatus == .authorized || authStatus == .limited), let firstAsset = firstAsset {
                    AssetThumbnailView(asset: firstAsset) { _ in }
                        .allowsHitTesting(false)
                        .frame(width: 48, height: 48)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.6), lineWidth: 2)
                        )
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

    /// Authorized but `recentAssets` hasn't propagated yet — show a small
    /// spinner instead of the generic photo icon so the user knows this
    /// square is loading, not empty. Disappears the moment `firstAsset`
    /// becomes non-nil (via the @Observable cascade from PhotoKitService).
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
