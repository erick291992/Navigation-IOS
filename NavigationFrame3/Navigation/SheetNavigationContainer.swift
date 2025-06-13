//
//  SheetNavigationContainer.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 6/9/25.
//
import SwiftUI

struct SheetNavigationContainer: View {
    let context: ModalContext
    @ObservedObject var navigationManager: NavigationManager

    @State private var currentID: UUID?

    var body: some View {
        let modalID = context.id

        NavigationStack(path: pushPathBinding(for: modalID)) {
            context.rootView
                .environmentObject(navigationManager)
                .navigationDestination(for: PushContext.self) { pushContext in
                    pushContext.makeView()
                        .environmentObject(navigationManager)
                }
        }
        .id(currentID) // ✅ Only changes when sheet changes
        .onAppear {
            if currentID != context.id {
                currentID = context.id
            }
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
