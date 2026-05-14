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
    let backgroundColor: Color?

    @State private var currentID: UUID?

    init(
        context: ModalContext,
        navigationManager: NavigationManager,
        backgroundColor: Color? = nil
    ) {
        self.context = context
        self.navigationManager = navigationManager
        self.backgroundColor = backgroundColor
    }

    @ViewBuilder
    var body: some View {
        let modalID = context.id
        let presentationOptions = context.sheetPresentationOptions

        NavigationStack(path: pushPathBinding(for: modalID)) {
            context.rootView
                .environment(\.navigationManager, navigationManager)
                .navigationDestination(for: PushContext.self) { pushContext in
                    pushContext.makeView()
                        .environment(\.navigationManager, navigationManager)
                }
        }
        .ifLet(backgroundColor) { $0.background($1) }
        .ifLet(presentationOptions?.detents) { $0.presentationDetents($1) }
        .ifLet(presentationOptions?.dragIndicator) { $0.presentationDragIndicator($1) }
            .id(currentID ?? context.id) // ← This guards against rebuild
            .onAppear {
                print("SheetNavigationContainer onAppear")
                guard currentID != context.id else { return }
                navigationManager.log("⚠️ Rebuilding SheetNavigationContainer due to ID change: \(String(describing: currentID)) → \(context.id)", level: .debug)
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

extension View {
    @ViewBuilder
    func ifLet<T, V: View>(_ value: T?, _ transform: (Self, T) -> V) -> some View {
        if let value { transform(self, value) } else { self }
    }
}
