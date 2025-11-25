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
    let backgroundColor: Color?

    @State private var currentID: UUID?

    init(
        context: ModalContext,
        navigationManager: NavigationManager,
        hideDefaultBackButton: Bool = false,
        backgroundColor: Color? = nil
    ) {
        self.context = context
        self.navigationManager = navigationManager
        self.hideDefaultBackButton = hideDefaultBackButton
        self.backgroundColor = backgroundColor
    }

    @ViewBuilder
    var body: some View {
        let modalID = context.id
        let presentationOptions = context.sheetPresentationOptions

        let navigationStack = NavigationStack(path: pushPathBinding(for: modalID)) {
            context.rootView
                .environment(\.navigationManager, navigationManager)
                .navigationDestination(for: PushContext.self) { pushContext in
                    pushContext.makeView()
                        .environment(\.navigationManager, navigationManager)
                        .navigationBarBackButtonHidden(hideDefaultBackButton)
                }
        }
        
        let baseView: AnyView = {
            if let backgroundColor = backgroundColor {
                return AnyView(navigationStack.background(backgroundColor))
            } else {
                return AnyView(navigationStack)
            }
        }()
        
        // Apply presentation modifiers conditionally, following SwiftUI's modifier pattern
        // These modifiers must be applied to the view presented in the sheet
        let viewWithPresentationModifiers: some View = {
            if let options = presentationOptions {
                var view: AnyView = AnyView(baseView)
                
                if let detents = options.detents {
                    view = AnyView(view.presentationDetents(detents))
                }
                if let dragIndicator = options.dragIndicator {
                    view = AnyView(view.presentationDragIndicator(dragIndicator))
                }
                
                return view
            } else {
                return AnyView(baseView)
            }
        }()
        
        viewWithPresentationModifiers
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
