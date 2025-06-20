//
//  NavigationCoordinator.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

struct NavigationCoordinator<Root: View>: View {
    let rootView: Root
    @ObservedObject var navigationManager: NavigationManager
    let scopeKey: String

    init(rootView: Root, key: String, manager: NavigationManager = NavigationManager()) {
        self.rootView = rootView
        self.navigationManager = manager
        self.scopeKey = key

        // Register this manager globally so it can be accessed from anywhere
        NavigationManagerRegistry.shared.register(manager, for: key)
        // ✅ Register root in full history
        let typeName = String(describing: Root.self)
        print("Registering root view: \(typeName)")
        let rootItem = NavigationItem(id: UUID(), viewTypeName: typeName, type: .push)
        manager.fullNavigationHistory.append(rootItem)
    }

    var body: some View {
        NavigationStack(path: $navigationManager.rootPushPath) {
            rootView
                .environmentObject(navigationManager)
                .navigationDestination(for: PushContext.self) { context in
                    context.makeView()
                        .environmentObject(navigationManager)
                }
        }
        .environmentObject(navigationManager)
        .sheet(item: topSheetContext) { context in
            if context.style == .sheet {
                SheetNavigationContainer(
                    context: context,
                    navigationManager: navigationManager
                )
            }
//            .environmentObject(navigationManager)
        }
        .fullScreenCover(item: topFullScreenContext) { context in
            if context.style == .fullScreen {
                SheetNavigationContainer(
                    context: context,
                    navigationManager: navigationManager
                )
            }
        }
    }

    /// A computed binding that allows SwiftUI to track the top-most sheet.
    private var topSheetContext: Binding<ModalContext?> {
        Binding(
            get: {
                navigationManager.modalStack.last(where: { $0.style == .sheet })
            },
            set: { newValue in
                if newValue == nil {
                    navigationManager.dismissSheet()
                }
            }
        )
    }

    private var topFullScreenContext: Binding<ModalContext?> {
        Binding(
            get: {
                navigationManager.modalStack.last(where: { $0.style == .fullScreen })
            },
            set: { newValue in
                if newValue == nil {
                    navigationManager.dismissSheet()
                }
            }
        )
    }

}
