//
//  ModalPresenter.swift
//  NavigationFrame3
//

import SwiftUI

/// Presents the next modal in `navigationManager.modalStack` from wherever it's attached.
///
/// The coordinator root attaches it with `parentID: nil`; every `SheetNavigationContainer`
/// attaches it with its own modal's id. That chain is what lets a lower sheet stay mounted
/// while the next one is presented on top of it (`.stacked`). See `childModal(of:)`.
///
/// Kept as its own modifier so only this body reads `modalStack` — the container's body
/// (and the sheet content inside it) isn't re-evaluated when modals above it change.
struct ModalPresenter: ViewModifier {
    let parentID: UUID?
    let navigationManager: NavigationManager
    let backgroundColor: Color?

    func body(content: Content) -> some View {
        let child = navigationManager.childModal(of: parentID)

        content
            .sheet(item: binding(for: child, style: .sheet)) { context in
                SheetNavigationContainer(
                    context: context,
                    navigationManager: navigationManager,
                    backgroundColor: backgroundColor
                )
                .onAppear {
                    navigationManager.log("🎭 Sheet presenting: \(context.id)", level: .info)
                }
            }
            .fullScreenCover(item: binding(for: child, style: .fullScreen)) { context in
                SheetNavigationContainer(
                    context: context,
                    navigationManager: navigationManager,
                    backgroundColor: backgroundColor
                )
                .onAppear {
                    navigationManager.log("🎭 FullScreen presenting: \(context.id)", level: .info)
                }
            }
    }

    /// Only one of the two bindings is non-nil at a time, so a sheet and a cover never
    /// compete from the same view. The setter dismisses by the child's id, so a late or
    /// repeated `nil` from SwiftUI after a programmatic removal is a no-op.
    private func binding(for child: ModalContext?, style: ModalPresentationStyle) -> Binding<ModalContext?> {
        Binding(
            get: { child?.style == style ? child : nil },
            set: { newValue in
                guard newValue == nil, let child, child.style == style else { return }
                navigationManager.log("👇 Interactive dismiss: \(child.id)", level: .debug)
                navigationManager.dismissModal(id: child.id)
            }
        )
    }
}
