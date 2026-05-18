import SwiftUI

/// Self-contained reuse-mode viewfinder. **No ViewModel** — it's a dumb view
/// that takes its data as props and forwards events via callbacks.
///
/// The history list is owned upstream (by `PickerViewModel`); we receive the
/// currently-selected `previewItem` as a parameter (TextField-style, mirrors
/// `LibraryViewfinderView`'s `previewAsset`). Renders a `HistoryPreviewer`
/// or the empty state.
struct HistoryViewfinderView: View {
    let history: [MediaItem]
    let previewItem: MediaItem?

    var body: some View {
        Group {
            if history.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No Session History"
                )
            } else {
                HistoryPreviewer(item: previewItem ?? history.first)
            }
        }
    }
}
