import SwiftUI

/// Generic empty-state view: icon + title + optional action button.
/// Replaces the inline `emptyLibraryState` and `emptyHistoryState` patterns
/// from the original monolithic UnifiedCreatorView.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let actionTitle: String?
    let onAction: (() -> Void)?

    init(
        icon: String,
        title: String,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    var body: some View {
        Color.black.overlay(
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.2))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))

                if let actionTitle = actionTitle, let onAction = onAction {
                    Button(actionTitle) {
                        // TODO: restore haptic feedback once Core Haptics
                        // pre-warm is solved without re-introducing the
                        // first-tap stall (see AssetGridView cell TODO).
                        onAction()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)
                }
            }
        )
    }
}
