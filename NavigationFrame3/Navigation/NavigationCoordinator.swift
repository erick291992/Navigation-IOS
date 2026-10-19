//
//  NavigationCoordinator.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

/// Helper class to automatically unregister manager when coordinator is deallocated
private class CoordinatorLifecycleObserver {
    let key: String
    
    init(key: String) {
        self.key = key
    }
    
    deinit {
        NavigationManagerRegistry.shared.unregister(key: key)
    }
}
struct NavigationCoordinator<Content: View>: View {
    let rootView: Content
    let customKey: String?
    let logLevel: NavigationManager.LogLevel
    let dismissalMode: NavigationManager.DismissalMode
    let sheetDismissalMode: NavigationManager.DismissalMode
    let dismissToMode: NavigationManager.DismissToMode
    let navigationStackColor: Color?
    let sheetBackgroundColor: Color?
    let modalPresentationMode: NavigationManager.ModalPresentationMode
    
    @Bindable var navigationManager: NavigationManager
    
    // Lifecycle observer that auto-unregisters manager when coordinator is deallocated
    @State private var lifecycleObserver: CoordinatorLifecycleObserver?
    
    private var key: String {
        customKey ?? String(describing: Content.self)
    }
    
    init(
        rootView: Content,
        customKey: String? = nil,
        dismissalMode: NavigationManager.DismissalMode = .topmost,
        sheetDismissalMode: NavigationManager.DismissalMode = .topmost,
        dismissToMode: NavigationManager.DismissToMode = .recent,
        logLevel: NavigationManager.LogLevel = NavigationManager.LogLevel.default,
        navigationStackColor: Color? = nil,
        sheetBackgroundColor: Color? = nil,
        modalPresentationMode: NavigationManager.ModalPresentationMode = .swap
    ) {
        self.rootView = rootView
        self.customKey = customKey
        self.dismissalMode = dismissalMode
        self.sheetDismissalMode = sheetDismissalMode
        self.dismissToMode = dismissToMode
        self.logLevel = logLevel
        self.navigationStackColor = navigationStackColor
        self.sheetBackgroundColor = sheetBackgroundColor
        self.modalPresentationMode = modalPresentationMode
        
        let targetKey = customKey ?? String(describing: Content.self)
        
        // Use existing manager from registry or create new one
        if let existingManager = NavigationManagerRegistry.shared.manager(forCustomKey: targetKey) {
            self.navigationManager = existingManager
            existingManager.log("🏗️ NavigationCoordinator reusing existing manager for key: \(targetKey)", level: .debug)
        } else {
            let newManager = NavigationManager()
            newManager.logLevel = logLevel
            newManager.defaultDismissalMode = dismissalMode
            newManager.defaultSheetDismissalMode = sheetDismissalMode
            newManager.defaultDismissToMode = dismissToMode
            self.navigationManager = newManager
            newManager.log("🏗️ NavigationCoordinator creating new manager for key: \(targetKey)", level: .info)
        }
        
        // Applied on every init (not just creation) so a registry-reused manager picks it up
        if self.navigationManager.defaultModalPresentationMode != modalPresentationMode {
            self.navigationManager.defaultModalPresentationMode = modalPresentationMode
        }

        // Register this manager globally so it can be accessed from anywhere
        NavigationManagerRegistry.shared.register(self.navigationManager, withCustomKey: targetKey)
        
        // Only register root if it's not already registered.
        // Root is named by view type (not customKey) so dismissTo(RootView.self) can land on it,
        // and so it matches the stale-stack reset in onAppear.
        let typeName = String(describing: Content.self)
        let existingRoot = self.navigationManager.fullNavigationHistory.first(where: { $0.location == .root })
        
        if existingRoot == nil {
            // No root registered yet - fresh manager
            self.navigationManager.log("Registering root view: \(typeName)", level: .info)
            let rootItem = NavigationItem(
                id: UUID(),
                viewTypeName: typeName,
                type: .push,
                location: .root
            )
            self.navigationManager.fullNavigationHistory.append(rootItem)
        } else if existingRoot?.viewTypeName != typeName {
            // ZOMBIE DETECTION: Root type changed! This means the old coordinator died without
            // proper cleanup (SwiftUI edge case). Reset the manager and register the new root.
            self.navigationManager.log("🧟 Zombie manager detected for key: \(targetKey) - root changed from \(existingRoot?.viewTypeName ?? "nil") to \(typeName). Resetting...", level: .info)
            self.navigationManager.reset()
            
            let rootItem = NavigationItem(
                id: UUID(),
                viewTypeName: typeName,
                type: .push,
                location: .root
            )
            self.navigationManager.fullNavigationHistory.append(rootItem)
        } else {
            self.navigationManager.log("Root view already registered: \(typeName)", level: .debug)
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
                .containerBackground(navigationStackColor ?? .clear, for: .navigation)
        }
        .environment(\.navigationManager, navigationManager)
        .modifier(ModalPresenter(
            parentID: nil,
            navigationManager: navigationManager,
            backgroundColor: sheetBackgroundColor ?? navigationStackColor
        ))
        .onAppear {
            if lifecycleObserver == nil {
                if !navigationManager.rootPushPath.isEmpty {
                    navigationManager.log("🧟 Fresh appearance with stale navigation stack detected for key: \(key). Resetting...", level: .info)
                    navigationManager.reset()
                    
                    let typeName = String(describing: Content.self)
                    let rootItem = NavigationItem(
                        id: UUID(),
                        viewTypeName: typeName,
                        type: .push,
                        location: .root
                    )
                    navigationManager.fullNavigationHistory.append(rootItem)
                }
                
                lifecycleObserver = CoordinatorLifecycleObserver(key: key)
            }
        }
    }
}
