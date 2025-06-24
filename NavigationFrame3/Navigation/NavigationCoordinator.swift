//
//  NavigationCoordinator.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

struct NavigationCoordinator<Root: View>: View {
    let rootView: Root
    @Bindable var navigationManager: NavigationManager
    let scopeKey: String
    
    init(rootView: Root, key: String, manager: NavigationManager? = nil) {
        self.rootView = rootView
        self.scopeKey = key
        
        // Use existing manager from registry or create new one
        if let existingManager = NavigationManagerRegistry.shared.manager(for: key) {
            self.navigationManager = existingManager
            print("🏗️ NavigationCoordinator reusing existing manager for key: \(key)")
        } else {
            self.navigationManager = manager ?? NavigationManager()
            print("🏗️ NavigationCoordinator creating new manager for key: \(key)")
        }

        print("🏗️ NavigationCoordinator init for key: \(key)")
        print("🏗️ NavigationManager instance: \(ObjectIdentifier(self.navigationManager))")

        // Register this manager globally so it can be accessed from anywhere
        NavigationManagerRegistry.shared.register(self.navigationManager, for: key)
        
        // Only register root if it's not already registered
        let typeName = String(describing: Root.self)
        if !self.navigationManager.fullNavigationHistory.contains(where: { $0.viewTypeName == typeName && $0.location == .root }) {
            print("Registering root view: \(typeName)")
            let rootItem = NavigationItem(
                id: UUID(),
                viewTypeName: typeName,
                type: .push,
                location: .root
            )
            self.navigationManager.fullNavigationHistory.append(rootItem)
        } else {
            print("Root view already registered: \(typeName)")
        }
    }

    var body: some View {
        NavigationStack(path: $navigationManager.rootPushPath) {
            rootView
                .environment(\.navigationManager, navigationManager)
                .navigationDestination(for: PushContext.self) { context in
                    context.makeView()
                        .environment(\.navigationManager, navigationManager)
                }
        }
        .environment(\.navigationManager, navigationManager)
        .sheet(item: topSheetContext) { context in
            if context.style == .sheet {
                SheetNavigationContainer(
                    context: context,
                    navigationManager: navigationManager
                )
                .onAppear {
                    print("🎭 Sheet presenting: \(context.id)")
                }
            }
        }
        .fullScreenCover(item: topFullScreenContext) { context in
            if context.style == .fullScreen {
                SheetNavigationContainer(
                    context: context,
                    navigationManager: navigationManager
                )
                .onAppear {
                    print("🎭 FullScreen presenting: \(context.id)")
                }
            }
        }
        .id("NavigationCoordinator-\(scopeKey)") // Use scopeKey as stable identifier
    }

    /// A computed binding that allows SwiftUI to track the top-most sheet.
    private var topSheetContext: Binding<ModalContext?> {
        Binding(
            get: {
                let topSheet = navigationManager.modalStack.last(where: { $0.style == .sheet })
                print("🔍 topSheetContext.get: \(topSheet?.id.uuidString ?? "NO SHEET")")
                print("🔍 Modal stack count: \(navigationManager.modalStack.count)")
                for (index, modal) in navigationManager.modalStack.enumerated() {
                    print("🔍 Modal \(index): \(modal.id) - style: \(modal.style)")
                }
                return topSheet
            },
            set: { newValue in
                print("🔍 topSheetContext.set: \(newValue?.id ?? UUID())")
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
