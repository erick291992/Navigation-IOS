import Foundation

/// Process-wide cache for the user's selected grid assets, keyed by
/// `selectionLimit`.
///
/// **Purpose**: preserve the user's selection (`[GridAsset]`) across SwiftUI's
/// upstream identity churn. See `ASSETGRID_FLICKER_POSTMORTEM.md`: the
/// `SheetNavigationContainer` AnyView wrapping causes the sheet content to
/// re-mount 4–5x per picker session. Each re-mount creates a fresh
/// `AssetGridViewModel` whose `state.selectedAssets` would otherwise default
/// to `[]`. By restoring from this cache in the VM's `init`, the user's
/// selection survives.
///
/// **Important**: this caches ONLY the selection (lightweight `[GridAsset]`
/// references — not photo image data). Image data is cached separately by
/// `ThumbnailCache` (in `PhotoKitService.swift`) and by Apple's PhotoKit
/// internal indexes. The grid's loaded `state.assets` is NOT cached — it
/// re-fetches from PhotoKit on each fresh VM (fast, ~10-30ms warm), and the
/// `AssetGridView` skeleton bridges the brief reload window.
///
/// **Access**: cleared per-session via `AssetGridViewModel.prepareForNewSession()`
/// (called from `MediaPickerModifier`'s `.sheet(onDismiss:)`) and indirectly
/// via `AssetGridViewModel.clearSession(for:)`. Views never touch this type
/// directly — only `AssetGridViewModel` (and its statics) read/write it.
@MainActor
enum AssetGridSelectionCache {
    private static var selections: [Int: [GridAsset]] = [:]

    static func selection(for selectionLimit: Int) -> [GridAsset] {
        selections[selectionLimit] ?? []
    }

    static func update(_ selection: [GridAsset], for selectionLimit: Int) {
        selections[selectionLimit] = selection
    }

    static func clear(for selectionLimit: Int) {
        selections.removeValue(forKey: selectionLimit)
    }
}
