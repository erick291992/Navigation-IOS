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
