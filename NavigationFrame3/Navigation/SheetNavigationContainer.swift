//
//  SheetNavigationContainer.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 6/9/25.
//
import SwiftUI

struct SheetNavigationContainer: View {
    let context: ModalContext
    @Bindable var navigationManager: NavigationManager

    @State private var currentID: UUID?

    var body: some View {
        let modalID = context.id

        NavigationStack(path: pushPathBinding(for: modalID)) {
            context.rootView
                .environment(\.navigationManager, navigationManager)
                .navigationDestination(for: PushContext.self) { pushContext in
                    pushContext.makeView()
                        .environment(\.navigationManager, navigationManager)
                }
        }
        .id(currentID ?? context.id) // ← This guards against rebuild
        .onAppear {
            guard currentID != context.id else { return }
            print("⚠️ Rebuilding SheetNavigationContainer due to ID change: \(String(describing: currentID)) → \(context.id)")
            currentID = context.id
        }
        .onAppear {
            print("📱 SheetNavigationContainer appeared for modal: \(context.id)")
        }
    }

    private func pushPathBinding(for id: UUID) -> Binding<[PushContext]> {
        Binding(
            get: { navigationManager.modalPushPaths[id] ?? [] },
            set: { newValue in
                navigationManager.modifyModalPushPath(for: id) { $0 = newValue }
            }
        )
    }
}
