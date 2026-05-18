import SwiftUI

/// Generic empty-state view: icon + title + a parent-supplied action area.
///
/// The action area is a `@ViewBuilder` so the caller can hand in whatever
/// tap target makes sense — a plain `Button`, a `PhotosPicker`, a link to
/// Settings, etc. Use the no-action init for purely visual empty states.
///
/// Examples:
/// ```swift
/// // No action — just icon + title
/// EmptyStateView(icon: "clock.arrow.circlepath", title: "No Session History")
///
/// // Button action
/// EmptyStateView(icon: "photo.on.rectangle", title: "No Recent Photos") {
///     Button("Open Library") { /* ... */ }
///         .font(.system(size: 14, weight: .bold))
///         .foregroundColor(.blue)
/// }
///
/// // PhotosPicker as the action target
/// EmptyStateView(icon: "photo.on.rectangle", title: "No Recent Photos") {
///     PhotosPicker(selection: $sel, maxSelectionCount: 1, matching: .images) {
///         Text("Open Library").foregroundColor(.blue)
///     }
/// }
/// ```
struct EmptyStateView<Action: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        Color.black.overlay(
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.2))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))

                action()
            }
        )
    }
}

/// Convenience init for the no-action case.
extension EmptyStateView where Action == EmptyView {
    init(icon: String, title: String) {
        self.init(icon: icon, title: title) { EmptyView() }
    }
}
