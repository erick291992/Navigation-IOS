//
//  NavigationManager.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

final class NavigationManager: ObservableObject {
    @Published var modalStack: [ModalContext] = []
    @Published var fullNavigationHistory: [NavigationItem] = []
    
    var topSheet: ModalContext? {
        modalStack.last
    }

    var topSheetBinding: Binding<ModalContext?> {
        Binding(
            get: { self.topSheet },
            set: { newValue in
                if newValue == nil {
                    self.dismissSheet()
                }
            }
        )
    }

//    func presentSheet<Content: View>(@ViewBuilder view: @escaping () -> Content) {
//        let context = ModalContext(rootView: AnyView(view()))
//        modalStack.append(context)
//        print("🎯 Presented sheet \(context.id)")
//        logModalStack()
//    }
    
    func presentSheet<Content: View>(@ViewBuilder view: @escaping () -> Content) {
        let context = ModalContext(rootView: AnyView(view()))
        modalStack.append(context)
        fullNavigationHistory.append(
            NavigationItem(
                id: context.id,
                viewTypeName: String(describing: Content.self),
                type: .sheet
            )
        )
        print("🎯 Presented sheet \(context.id) of type \(Content.self)")
        logModalStack()
    }



    func dismissSheet() {
        if let removed = modalStack.popLast() {
            print("❎ Dismissed sheet \(removed.id)")
            logModalStack()
        }
    }

    func dismissTo<Content: View>(_ target: Content.Type) {
        print("📜 Full History:")
        for item in fullNavigationHistory {
            print("• \(item.typeName)")
        }

        let targetName = String(describing: target)

        guard let targetIndex = fullNavigationHistory.lastIndex(where: {
            $0.viewTypeName == targetName
        }) else {
            print("❌ Could not find \(targetName) in full history")
            return
        }

        let targetItem = fullNavigationHistory[targetIndex]

        if targetItem.type == .sheet {
            // It's a modal, trim modalStack using its UUID
            guard let modalIndex = modalStack.lastIndex(where: { $0.id == targetItem.id }) else {
                print("❌ Matching modalContext not found for \(targetName)")
                return
            }

            modalStack = Array(modalStack.prefix(modalIndex + 1))
        } else {
            // Not a modal, just clear all modals
            modalStack.removeAll()
        }

        // Trim the full history
        fullNavigationHistory = Array(fullNavigationHistory.prefix(targetIndex + 1))

        print("🔙 Dismissed to \(targetName)")
        logModalStack()
    }



    
//    func dismissTo(_ viewTypeName: String) -> Bool {
//        if let index = modalStack.lastIndex(where: { $0.rootView.typeName == viewTypeName }) {
//            modalStack = Array(modalStack.prefix(index + 1))
//            logModalStack()
//            return true
//        }
//        return false
//    }

    func reset() {
        modalStack.removeAll()
        print("🧼 NavigationManager sheet stack reset")
    }

    private func logModalStack() {
        print("🧱 Modal Stack:")
        for context in modalStack {
            print("• \(context.id)")
        }
    }
}
