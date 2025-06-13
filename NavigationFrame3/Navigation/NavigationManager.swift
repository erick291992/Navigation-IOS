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

    // ✅ onDismiss triggered when views are popped from root stack
    @Published var rootPushPath: [PushContext] = [] {
        didSet {
            guard oldValue.count > rootPushPath.count else { return }
            let removed = oldValue.suffix(from: rootPushPath.count)
            for context in removed {
                print("🔥 Native pop: \(context.viewTypeName) [root]")
                context.onDismiss?()
            }
        }
    }

    // ✅ Use `modifyModalPushPath` to trigger dismiss detection
    @Published var modalPushPaths: [UUID: [PushContext]] = [:]

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
    
    enum SheetPresentationStyle {
        case stack         // ➕ Add to top of stack (default)
        case replaceLast   // 🔁 Remove top sheet, then present new one
        case replaceAll    // 🔄 Remove all sheets, then present new one
    }


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
            if modalStack.contains(where: { $0.id == modalID }) {
                modifyModalPushPath(for: modalID) { $0.append(context) }
                print("📦 Pushed view of type \(context.viewTypeName) [context: modal \(modalID.uuidString.prefix(4))]")
            } else {
                print("⚠️ Tried to push into modal \(modalID.uuidString.prefix(4)), but it's no longer mounted. Falling back to root.")
                rootPushPath.append(context)
            }
        } else {
            rootPushPath.append(context)
            print("📦 Pushed view of type \(context.viewTypeName) [context: root]")
        }

        fullNavigationHistory.append(
            NavigationItem(id: context.id, viewTypeName: context.viewTypeName, type: .push)
        )
    }

    func presentSheet<Content: View>(
        style: SheetPresentationStyle = .stack,
        @ViewBuilder view: @escaping () -> Content,
        onDismiss: (() -> Void)? = nil
    ) {
        switch style {
        case .replaceLast:
            if let removed = modalStack.popLast() {
                print("🔥 Replacing last modal: \(removed.id.uuidString.prefix(4))")
                removed.onDismiss?()
                modalPushPaths[removed.id] = nil
            }

        case .replaceAll:
            for context in modalStack.reversed() {
                print("🔥 Replacing all → dismissing modal: \(context.id.uuidString.prefix(4))")
                context.onDismiss?()
                modalPushPaths[context.id] = nil
            }
            modalStack.removeAll()

        case .stack:
            break // Default: allow stacking
        }

        let context = ModalContext(
            makeView: { AnyView(view()) },
            onDismiss: onDismiss
        )

        // ✅ Only initialize if not already present
        if modalPushPaths[context.id] == nil {
            print("🆕 Initializing push path for modal \(context.id.uuidString.prefix(4))")
            modalPushPaths[context.id] = []
        } else {
            print("♻️ Reusing existing push path for modal \(context.id.uuidString.prefix(4))")
        }

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
        guard let removed = modalStack.popLast() else { return }

        let removedID = removed.id
        print("❎ Dismissed sheet \(removedID)")

        // ✅ Trigger onDismiss for all pushed views in the dismissed sheet
        if let removedStack = modalPushPaths[removedID] {
            for context in removedStack.reversed() {
                print("🔥 Modal push onDismiss → \(context.viewTypeName)")
                context.onDismiss?()
            }
        }

        // ✅ Remove push path only for the dismissed modal
        modalPushPaths[removedID] = nil

        // ✅ Trigger modal-level onDismiss last
        removed.onDismiss?()

        // 🧱 Re-log modal stack for visibility
        logModalStack()
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
                for context in poppedContexts.reversed() {
                    print("🔥 Intermediate modal onDismiss → \(context.id.uuidString.prefix(4))")
                    context.onDismiss?()
                }
            } else if let last = poppedContexts.dropLast().last {
                print("🔥 onDismiss for landing modal: \(last.id.uuidString.prefix(4))")
                last.onDismiss?()
            }

            let removedModals = modalStack.suffix(from: modalIndex + 1)
            modalStack = Array(modalStack.prefix(modalIndex + 1))

            for context in removedModals {
                modalPushPaths[context.id] = nil
            }

            let modalID = targetItem.id
            if let pushStack = modalPushPaths[modalID] {
                for context in pushStack.reversed() {
                    print("🔥 Modal push onDismiss → \(context.id.uuidString.prefix(4))")
                    context.onDismiss?()
                }
                updateModalPushPath(for: modalID, newValue: [])
            }

        } else {
            let removedModals = modalStack
            if triggerIntermediateDismissals {
                for context in removedModals.reversed() {
                    print("🔥 Intermediate modal onDismiss → \(context.id.uuidString.prefix(4))")
                    context.onDismiss?()
                }
            } else if let first = modalStack.first {
                print("🔥 onDismiss for modal above root: \(first.id.uuidString.prefix(4))")
                first.onDismiss?()
            }

            modalStack.removeAll()
            for modal in removedModals {
                modalPushPaths.removeValue(forKey: modal.id)
            }

            if let pushIndex = rootPushPath.firstIndex(where: { $0.viewTypeName == targetItem.viewTypeName }) {
                let removed = rootPushPath.suffix(from: pushIndex + 1)
                if triggerIntermediateDismissals {
                    for context in removed.reversed() {
                        print("🔥 Root push onDismiss → \(context.id.uuidString.prefix(4))")
                        context.onDismiss?()
                    }
                } else if let last = removed.dropLast().last {
                    print("🔥 onDismiss for root landing: \(last.id.uuidString.prefix(4))")
                    last.onDismiss?()
                }
                rootPushPath = Array(rootPushPath.prefix(through: pushIndex))
            } else if fullNavigationHistory.first?.viewTypeName == targetItem.viewTypeName {
                for context in rootPushPath.reversed() {
                    print("🔥 Root push onDismiss → \(context.id.uuidString.prefix(4))")
                    context.onDismiss?()
                }
                rootPushPath = []
            }
        }

        logModalStack()
    }

    private func updateModalPushPath(for modalID: UUID, newValue: [PushContext]) {
        let oldValue = modalPushPaths[modalID] ?? []
        modalPushPaths[modalID] = newValue

        if oldValue.count > newValue.count {
            let removed = oldValue.suffix(from: newValue.count)
            for context in removed {
                print("🔥 Native pop: \(context.viewTypeName) [modal \(modalID.uuidString.prefix(4))]")
                context.onDismiss?()
            }
        }
    }

    /// ✅ Use this everywhere instead of direct modalPushPaths[...] = ...
    func modifyModalPushPath(for modalID: UUID, mutate: (inout [PushContext]) -> Void) {
        var path = modalPushPaths[modalID, default: []]   // current value
        mutate(&path)                                     // caller changes it
        updateModalPushPath(for: modalID, newValue: path) // diff-check & publish
    }


    func reset() {
        modalStack.removeAll()
        modalPushPaths.removeAll()
        rootPushPath = []
        fullNavigationHistory = []
        print("🧼 NavigationManager fully reset")
    }

    private func logModalStack() {
        print("🧱 Modal Stack:")
        for context in modalStack {
            print("• \(context.id)")
        }
    }
}
