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
    
    func presentSheet<Content: View>(
        @ViewBuilder view: @escaping () -> Content,
        onDismiss: (() -> Void)? = nil
    ) {
        let context = ModalContext(
            makeView: { AnyView(view()) },
            onDismiss: onDismiss
        )

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
            removed.onDismiss?() // ✅ Run the handler
            logModalStack()
        }
    }
    
    func dismissTo<Content: View>(
        _ target: Content.Type,
        triggerIntermediateDismissals: Bool = false
    ) {
        print("📜 Full Navigation History:")
        for item in fullNavigationHistory {
            print("• \(item.viewTypeName) [\(item.type.rawValue)]")
        }

        let targetName = String(describing: target)

        guard let targetIndex = fullNavigationHistory.lastIndex(where: {
            $0.viewTypeName == targetName
        }) else {
            print("❌ Could not find \(targetName) in full history")
            return
        }

        print("🎯 Attempting to dismiss to: \(targetName)")
        let targetItem = fullNavigationHistory[targetIndex]

        if targetItem.type == .sheet {
            guard let modalIndex = modalStack.lastIndex(where: { $0.id == targetItem.id }) else {
                print("❌ Matching modalContext not found for \(targetName)")
                return
            }

            let poppedContexts = modalStack.suffix(from: modalIndex + 1)

            if triggerIntermediateDismissals {
                print("🔥 Triggering ALL popped modal onDismiss handlers (in reverse):")
                for context in poppedContexts.reversed() {
                    print("   • onDismiss → \(context.id.uuidString.prefix(4))")
                    context.onDismiss?()
                }
            } else if let last = poppedContexts.dropLast().last {
                print("🔥 Triggering onDismiss for modal we're landing on: \(last.id.uuidString.prefix(4))")
                last.onDismiss?()
            }

            modalStack = Array(modalStack.prefix(modalIndex + 1))
        } else {
            // 🧹 Dismissing to a push root — all modals go
            let poppedContexts = modalStack

            if triggerIntermediateDismissals {
                print("🔥 Triggering ALL modal onDismiss handlers (in reverse):")
                for context in poppedContexts.reversed() {
                    print("   • onDismiss → \(context.id.uuidString.prefix(4))")
                    context.onDismiss?()
                }
            } else if let first = modalStack.first {
                print("🔥 Triggering onDismiss for modal directly above push root: \(first.id.uuidString.prefix(4))")
                first.onDismiss?()
            }

            modalStack.removeAll()
            print("✅ Cleared modalStack")
        }

        fullNavigationHistory = Array(fullNavigationHistory.prefix(targetIndex + 1))
        print("📜 Trimmed fullNavigationHistory to:")
        for item in fullNavigationHistory {
            print("• \(item.viewTypeName) [\(item.type.rawValue)]")
        }

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
