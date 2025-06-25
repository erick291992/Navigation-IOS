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
    let hideDefaultBackButton: Bool

    @State private var currentID: UUID?

    init(context: ModalContext, navigationManager: NavigationManager, hideDefaultBackButton: Bool = false) {
        self.context = context
        self.navigationManager = navigationManager
        self.hideDefaultBackButton = hideDefaultBackButton
    }

    var body: some View {
        let modalID = context.id

        NavigationStack(path: pushPathBinding(for: modalID)) {
            context.rootView
                .environment(\.navigationManager, navigationManager)
                .navigationDestination(for: PushContext.self) { pushContext in
                    pushContext.makeView()
                        .environment(\.navigationManager, navigationManager)
                        .navigationBarBackButtonHidden(hideDefaultBackButton)
                }
        }
        .id(currentID ?? context.id) // ← This guards against rebuild
        .onAppear {
            print("SheetNavigationContainer onAppear")
            guard currentID != context.id else { return }
            navigationManager.log("⚠️ Rebuilding SheetNavigationContainer due to ID change: \(String(describing: currentID)) → \(context.id)", level: .info)
            currentID = context.id
        }
        .onAppear {
            navigationManager.log("📱 SheetNavigationContainer appeared for modal: \(context.id)", level: .info)
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
