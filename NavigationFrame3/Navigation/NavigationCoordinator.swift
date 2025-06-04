//
//  NavigationCoordinator.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

struct NavigationCoordinator<Root: View>: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    let rootView: Root
    
    init(rootView: Root) {
        self.rootView = rootView

        // Register the root view type (only once)
        let rootType = String(describing: Root.self)
        if NavigationManager.shared.rootViewTypeName == nil {
            NavigationManager.shared.rootViewTypeName = rootType
            print("📌 Registered root view type:", rootType)
        }
    }


    var body: some View {
        NavigationStack(path: $navigationManager.pushPath) {
            rootView
            
                .navigationDestination(for: NavigationItem.self) { item in
                    item.viewFactory()
                }
                .sheet(item: sheetContextBinding) { modal in
                    NavigationStack(path: Binding(
                        get: { modalStack(for: modal.id)?.pushPath ?? [] },
                        set: { newValue in updateModal(modal.id, newPushPath: newValue) }
                    )) {
                        modal.root.viewFactory()
                            .navigationDestination(for: NavigationItem.self) { item in
                                item.viewFactory()
                            }
                    }
                }
                .fullScreenCover(item: fullscreenBinding) { modal in
                    NavigationStack(path: Binding(
                        get: { modalStack(for: modal.id)?.pushPath ?? [] },
                        set: { newValue in updateModal(modal.id, newPushPath: newValue) }
                    )) {
                        modal.viewFactory()
                            .navigationDestination(for: NavigationItem.self) { item in
                                item.viewFactory()
                            }
                    }
                }
        }
    }

    private var sheetBinding: Binding<NavigationItem?> {
        Binding(
            get: { navigationManager.modalStack.last(where: { $0.type == .sheet })?.root },
            set: { if $0 == nil { navigationManager.dismissTopModal() } }
        )
    }
    
    private var sheetContextBinding: Binding<NavigationManager.ModalContext?> {
        Binding(
            get: { navigationManager.modalStack.last(where: { $0.type == .sheet }) },
            set: { newValue in
                if newValue == nil {
                    navigationManager.dismissTopModal()
                }
            }
        )
    }

    private var fullscreenBinding: Binding<NavigationItem?> {
        Binding(
            get: { navigationManager.modalStack.last(where: { $0.type == .fullscreen })?.root },
            set: { if $0 == nil { navigationManager.dismissTopModal() } }
        )
    }

    private func modalStack(for id: UUID) -> NavigationManager.ModalContext? {
        navigationManager.modalStack.first(where: { $0.id == id })
    }

    private func updateModal(_ id: UUID, newPushPath: [NavigationItem]) {
        if let index = navigationManager.modalStack.firstIndex(where: { $0.id == id }) {
            navigationManager.modalStack[index].pushPath = newPushPath
        }
    }
}
