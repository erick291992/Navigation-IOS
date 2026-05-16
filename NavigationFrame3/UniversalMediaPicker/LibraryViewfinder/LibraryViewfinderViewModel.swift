import Foundation
import Photos
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
    private let photoKit = PhotoKitService.shared

    /// Per-VM loading flag for the recents fetch the VM itself initiates.
    public var isLoadingRecents = false

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

    /// Called from the view's `.task`. Idempotent — guards on data presence
    /// so warm caches (from the modifier prewarm) don't trigger a duplicate
    /// fetch and spurious spinner.
    public func loadRecentsIfNeeded() async {
        guard !hasRecents else { return }
        guard authStatus == .authorized || authStatus == .limited else { return }
        isLoadingRecents = true
        defer { isLoadingRecents = false }
        await photoKit.fetchRecentAssets()
    }
}
