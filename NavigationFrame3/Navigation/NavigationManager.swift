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
    @Published var rootPushPath: [PushContext] = []
    @Published var modalPushPaths: [UUID: [PushContext]] = [:] // key = modal ID

//    var currentContextID: UUID? {
//        modalStack.last?.id
//    }

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
    
    func push<Content: View>(
        @ViewBuilder view: @escaping () -> Content,
        onDismiss: (() -> Void)? = nil
    ) {
        let contextID = modalStack.last?.id
        let context = PushContext(
            makeView: { AnyView(view()) },
            viewTypeName: String(describing: Content.self),
            onDismiss: onDismiss
        )

        if let modalID = contextID {
            modalPushPaths[modalID, default: []].append(context)
        } else {
            rootPushPath.append(context)
        }

        fullNavigationHistory.append(
            NavigationItem(id: context.id, viewTypeName: context.viewTypeName, type: .push)
        )

        print("📦 Pushed view of type \(context.viewTypeName) [context: \(contextID?.uuidString.prefix(4) ?? "root")]")
    }



    
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
            let modalID = targetItem.id
            if let pushStack = modalPushPaths[modalID] {
                let removed = pushStack.reversed() // all pushed views in this sheet
                for context in removed {
                    print("🔥 Triggering modal push onDismiss → \(context.id.uuidString.prefix(4))")
                    context.onDismiss?()
                }
                modalPushPaths[modalID] = [] // completely reset it
                print("🧼 Cleared modal push path for modal \(modalID.uuidString.prefix(4))")
            }

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
            
            // ✅ Trim the push stack (root or modal)
            let isInRoot = true // right now always root since we're dismissing to root context
            if isInRoot {
                if let pushIndex = rootPushPath.firstIndex(where: { $0.viewTypeName == targetItem.viewTypeName }) {
                    let oldPath = rootPushPath
                    rootPushPath = Array(rootPushPath.prefix(through: pushIndex))
                    
                    let removed = oldPath.suffix(from: pushIndex + 1)

                    if triggerIntermediateDismissals {
                        print("🔥 Triggering ALL push onDismiss handlers (in reverse):")
                        for context in removed.reversed() {
                            print("   • onDismiss → \(context.id.uuidString.prefix(4))")
                            context.onDismiss?()
                        }
                    } else if let last = removed.dropLast().last {
                        print("🔥 Triggering push onDismiss for view we're landing on: \(last.id.uuidString.prefix(4))")
                        last.onDismiss?()
                    }
                    
                    print("🧼 Trimmed rootPushPath to remove views above \(targetItem.viewTypeName)")
                } else if fullNavigationHistory.first?.viewTypeName == targetItem.viewTypeName {
                    // We're dismissing to the push *root*, e.g., ViewB
                    let popped = rootPushPath

                    if triggerIntermediateDismissals {
                        print("🔥 Triggering ALL push onDismiss handlers (in reverse):")
                        for context in popped.reversed() {
                            print("   • onDismiss → \(context.id.uuidString.prefix(4))")
                            context.onDismiss?()
                        }
                    } else if let last = popped.dropLast().last {
                        print("🔥 Triggering push onDismiss for view we're landing on: \(last.id.uuidString.prefix(4))")
                        last.onDismiss?()
                    }

                    rootPushPath = []
                    print("🧼 Cleared rootPushPath back to push root: \(targetItem.viewTypeName)")

                } else {
                    print("⚠️ Could not find push context for \(targetItem.viewTypeName)")
                }
            }
            
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
