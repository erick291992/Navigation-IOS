//
//  NavigationCoordinator.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

struct NavigationCoordinator<Content: View>: View {
    let rootView: Content
    let key: String
    let logLevel: NavigationManager.LogLevel
    let hideDefaultBackButton: Bool
    let dismissalMode: NavigationManager.DismissalMode
    let sheetDismissalMode: NavigationManager.DismissalMode
    let dismissToMode: NavigationManager.DismissToMode
    
    @Bindable var navigationManager: NavigationManager
    
    init(
        rootView: Content, 
        key: String, 
        hideDefaultBackButton: Bool = false,
        dismissalMode: NavigationManager.DismissalMode = .topmost,
        sheetDismissalMode: NavigationManager.DismissalMode = .topmost,
        dismissToMode: NavigationManager.DismissToMode = .recent,
        logLevel: NavigationManager.LogLevel = NavigationManager.LogLevel.default
    ) {
        self.rootView = rootView
        self.key = key
        self.hideDefaultBackButton = hideDefaultBackButton
        self.dismissalMode = dismissalMode
        self.sheetDismissalMode = sheetDismissalMode
        self.dismissToMode = dismissToMode
        self.logLevel = logLevel
        
        // Use existing manager from registry or create new one
        if let existingManager = NavigationManagerRegistry.shared.manager(for: key) {
            self.navigationManager = existingManager
            navigationManager.log("🏗️ NavigationCoordinator reusing existing manager for key: \(key)", level: .info)
            // Don't override log level - keep user's setting
        } else {
            let newManager = NavigationManager()
            newManager.logLevel = logLevel
            // Set default dismissal modes
            newManager.defaultDismissalMode = dismissalMode
            newManager.defaultSheetDismissalMode = sheetDismissalMode
            newManager.defaultDismissToMode = dismissToMode
            self.navigationManager = newManager
            navigationManager.log("🏗️ NavigationCoordinator creating new manager for key: \(key)", level: .info)
        }
        
        navigationManager.log("🏗️ NavigationCoordinator init for key: \(key)", level: .info)
        navigationManager.log("🏗️ NavigationManager instance: \(ObjectIdentifier(self.navigationManager))", level: .debug)

        // Register this manager globally so it can be accessed from anywhere
        NavigationManagerRegistry.shared.register(self.navigationManager, for: key)
        
        // Only register root if it's not already registered
        let typeName = String(describing: Content.self)
        if !self.navigationManager.fullNavigationHistory.contains(where: { $0.viewTypeName == typeName && $0.location == .root }) {
            navigationManager.log("Registering root view: \(typeName)", level: .info)
            let rootItem = NavigationItem(
                id: UUID(),
                viewTypeName: typeName,
                type: .push,
                location: .root
            )
            self.navigationManager.fullNavigationHistory.append(rootItem)
        } else {
            navigationManager.log("Root view already registered: \(typeName)", level: .info)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationManager.rootPushPath) {
            rootView
                .environment(\.navigationManager, navigationManager)
                .navigationDestination(for: PushContext.self) { context in
                    context.makeView()
                        .environment(\.navigationManager, navigationManager)
                        .navigationBarBackButtonHidden(hideDefaultBackButton)
                }
        }
        .environment(\.navigationManager, navigationManager)
        .sheet(item: topSheetContext) { context in
            if context.style == .sheet {
                SheetNavigationContainer(
                    context: context,
                    navigationManager: navigationManager,
                    hideDefaultBackButton: hideDefaultBackButton
                )
                .onAppear {
                    navigationManager.log("🎭 Sheet presenting: \(context.id)", level: .info)
                }
            }
        }
        .fullScreenCover(item: topFullScreenContext) { context in
            if context.style == .fullScreen {
                SheetNavigationContainer(
                    context: context,
                    navigationManager: navigationManager,
                    hideDefaultBackButton: hideDefaultBackButton
                )
                .onAppear {
                    navigationManager.log("🎭 FullScreen presenting: \(context.id)", level: .info)
                }
            }
        }
        .id("NavigationCoordinator-\(key)") // Use key as stable identifier
    }

    /// A computed binding that allows SwiftUI to track the top-most sheet.
    private var topSheetContext: Binding<ModalContext?> {
        Binding(
            get: {
                let topSheet = navigationManager.modalStack.last(where: { $0.style == .sheet })
                navigationManager.log("🔍 topSheetContext.get: \(topSheet?.id.uuidString ?? "NO SHEET")", level: .debug)
                navigationManager.log("🔍 Modal stack count: \(navigationManager.modalStack.count)", level: .debug)
                for (index, modal) in navigationManager.modalStack.enumerated() {
                    navigationManager.log("🔍 Modal \(index): \(modal.id) - style: \(modal.style)", level: .debug)
                }
                return topSheet
            },
            set: { newValue in
                navigationManager.log("🔍 topSheetContext.set: \(newValue?.id ?? UUID())", level: .debug)
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
