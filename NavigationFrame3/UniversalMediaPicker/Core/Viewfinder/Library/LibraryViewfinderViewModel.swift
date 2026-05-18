import Foundation
import Photos
import UIKit
import Observation

/// `@MainActor @Observable` view model for `LibraryViewfinderView`.
///
/// Self-contained — instantiated inside the view via `@State`. Proxies the
/// shared `PhotoKitService` state via computed properties (View → VM rule),
/// owns the per-VM loading state, and forwards the limited-picker intent.
///
/// `previewAsset` is NOT held here — it's owned by `PickerViewModel` and
/// passed DOWN to the view as a `let` parameter (TextField-style primitive
/// pattern). The VM provides a `displayAsset(preferring:)` helper that
/// applies the fallback to `recentAssets.first`.
@MainActor
@Observable
public final class LibraryViewfinderViewModel {
    private let photoKit: PhotoKitService

    /// Load progress for recents. One state variable, three explicit
    /// states — replaces an earlier two-boolean shape (isLoadingRecents +
    /// hasAttemptedLoad) that had four combinations but only three valid
    /// ones. Mirrors Apple's `AsyncImage.Phase` idiom: idle → loading →
    /// loaded, no impossible "loaded but still loading" combo
    /// representable.
    public enum LoadPhase: Equatable {
        case idle      // not yet attempted (view shows spinner)
        case loading   // fetch in flight (view shows spinner)
        case loaded    // attempted; data lives in `recentAssets` (or doesn't, if genuinely empty)
    }

    public var loadPhase: LoadPhase

    public init(photoKit: PhotoKitService = .shared) {
        self.photoKit = photoKit
        // If the modifier's prewarm already populated recents before this
        // VM mounted, skip `.idle` entirely — no spinner flash, view
        // renders the previewer on its very first frame.
        self.loadPhase = photoKit.recentAssets.isEmpty ? .idle : .loaded
    }

    // MARK: - Computed proxies

    public var recentAssets: [PHAsset] { photoKit.recentAssets }
    public var authStatus: PHAuthorizationStatus { photoKit.authStatus }
    public var hasRecents: Bool { !photoKit.recentAssets.isEmpty }

    // MARK: - Display helpers

    /// Resolves the asset to show in the previewer. The parent's `previewAsset`
    /// (when the user has tapped one in the grid) takes precedence; otherwise
    /// we fall back to the first recent asset.
    public func displayAsset(preferring preview: PHAsset?) -> PHAsset? {
        preview ?? photoKit.recentAssets.first
    }

    // MARK: - Intent

    /// Opens the iOS limited library picker. Only meaningful when
    /// `authStatus == .limited`.
    public func openLimitedPicker() {
        photoKit.openLimitedPicker()
    }

    /// Called from the view's `.task`. Idempotent — re-entry while
    /// `.loaded` is a no-op. Always settles `loadPhase` to `.loaded` on
    /// exit (including early-return guards) so the view can transition
    /// out of its initial spinner state regardless of which branch we took.
    public func loadRecentsIfNeeded() async {
        guard loadPhase != .loaded else { return }     // already settled
        guard authStatus == .authorized || authStatus == .limited else {
            loadPhase = .loaded                          // no auth to fetch — attempt is done
            return
        }
        guard !hasRecents else {
            loadPhase = .loaded                          // warm prewarm raced past us
            return
        }
        loadPhase = .loading
        await photoKit.fetchRecentAssets()
        loadPhase = .loaded
    }

    // MARK: - Previewer image (called by LibraryViewfinderView per previewer)

    /// Synchronous thumbnail peek. The view passes the result to
    /// `LibraryPreviewer` as `initialImage` so the previewer paints on its
    /// first frame without an async hop (and flips to a tapped asset's
    /// cached image instantly while the high-res upgrade loads).
    public func thumbnail(for asset: PHAsset?) -> UIImage? {
        guard let asset else { return nil }
        return photoKit.cachedThumbnail(for: asset)
    }

    /// Async high-res fetch for the previewer at `previewerTargetSize`.
    /// The view passes this as `loadAsync`; the previewer awaits it in
    /// `.task(id:)`, which auto-cancels when the displayed asset changes
    /// (user tapped a different grid cell) and starts a new fetch keyed
    /// to the new asset.
    public func requestThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            photoKit.loadThumbnail(for: asset, size: PhotoKitService.previewerTargetSize) { image in
                continuation.resume(returning: image)
            }
        }
    }
}
