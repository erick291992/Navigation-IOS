//
//  NavigationManager.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

@Observable
final class NavigationManager {
    var modalStack: [ModalContext] = []
    var fullNavigationHistory: [NavigationItem] = []

    // ✅ onDismiss triggered when views are popped from root stack
    var rootPushPath: [PushContext] = [] {
        didSet {
            guard oldValue.count > rootPushPath.count else { return }
            let removed = oldValue.suffix(from: rootPushPath.count)
            for context in removed {
                if suppressedDismissIDs.contains(context.id) {
                    print("🚫 Suppressed native pop: \(context.viewTypeName)")
                    suppressedDismissIDs.remove(context.id)
                } else {
                    print("🔥 Native pop: \(context.viewTypeName) [root]")
                    context.onDismiss?()
                }
            }
        }
    }

    // ✅ Use `modifyModalPushPath` to trigger dismiss detection
    var modalPushPaths: [UUID: [PushContext]] = [:]
    private var suppressedDismissIDs: Set<UUID> = []

    enum SheetPresentationStyle {
        case stack         // ➕ Add to top of stack (default)
        case replaceLast   // 🔁 Remove top sheet, then present new one
        case replaceAll    // 🔄 Remove all sheets, then present new one
    }

    enum DismissalMode {
        case all        // Call onDismiss for every removed view (intermediate)
        case landing    // Only call onDismiss for the view you land on (the last one removed)
        case parent     // Only call onDismiss for the direct parent of the current view
    }

    enum DismissToMode {
        case root      // Go to the first occurrence (root)
        case recent    // Go to the most recent occurrence
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
                let index = (modalPushPaths[modalID]?.count ?? 0)
                modifyModalPushPath(for: modalID) { $0.append(context) }
                print("📦 Pushed view of type \(context.viewTypeName) [context: modal \(modalID.uuidString.prefix(4))]")
                fullNavigationHistory.append(
                    NavigationItem(
                        id: context.id,
                        viewTypeName: context.viewTypeName,
                        type: .push,
                        location: .modalPush(modalID: modalID, index: index)
                    )
                )
            } else {
                let index = rootPushPath.count
                rootPushPath.append(context)
                print("⚠️ Tried to push into modal \(modalID.uuidString.prefix(4)), but it's no longer mounted. Falling back to root.")
                fullNavigationHistory.append(
                    NavigationItem(
                        id: context.id,
                        viewTypeName: context.viewTypeName,
                        type: .push,
                        location: .rootPush(index: index)
                    )
                )
            }
        } else {
            let index = rootPushPath.count
            rootPushPath.append(context)
            print("📦 Pushed view of type \(context.viewTypeName) [context: root]")
            fullNavigationHistory.append(
                NavigationItem(
                    id: context.id,
                    viewTypeName: context.viewTypeName,
                    type: .push,
                    location: .rootPush(index: index)
                )
            )
        }
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
            style: .sheet,
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

        let index = modalStack.count
        modalStack.append(context)

        print("📝 Adding modal to stack: \(context.id) at index \(index)")
        print("📝 Modal stack count after adding: \(modalStack.count)")

        fullNavigationHistory.append(
            NavigationItem(
                id: context.id,
                viewTypeName: String(describing: Content.self),
                type: .sheet,
                location: .modalStack(index: index)
            )
        )

        print("🎯 Presented sheet \(context.id) of type \(Content.self)")
        logModalStack()
    }

    func presentFullScreen<Content: View>(
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
            break
        }

        let context = ModalContext(
            style: .fullScreen,
            makeView: view,
            onDismiss: onDismiss
        )

        if modalPushPaths[context.id] == nil {
            print("🆕 Initializing push path for modal \(context.id.uuidString.prefix(4))")
            modalPushPaths[context.id] = []
        }

        let index = modalStack.count
        modalStack.append(context)

        fullNavigationHistory.append(
            NavigationItem(
                id: context.id,
                viewTypeName: String(describing: Content.self),
                type: .fullscreen,
                location: .modalStack(index: index)
            )
        )

        print("🎯 Presented fullScreenCover \(context.id) of type \(Content.self)")
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

    func dismissPush() {
        // Check if a modal is active
        if let modalID = modalStack.last?.id {
            guard var currentStack = modalPushPaths[modalID], !currentStack.isEmpty else { return }
            
            let removed = currentStack.removeLast()
            print("❎ Dismissed pushed view: \(removed.viewTypeName) [modal \(modalID.uuidString.prefix(4))]")
            removed.onDismiss?()

            updateModalPushPath(for: modalID, newValue: currentStack)
            
            // Also remove from full navigation history
            fullNavigationHistory.removeAll { $0.id == removed.id }

        } else {
            // Otherwise, dismiss from root push stack
            guard !rootPushPath.isEmpty else { return }

            let removed = rootPushPath.removeLast()
            print("❎ Dismissed pushed view: \(removed.viewTypeName) [root]")
            removed.onDismiss?()

            // Since we manually modified rootPushPath, manually publish it
            rootPushPath = rootPushPath

            // Also remove from full navigation history
            fullNavigationHistory.removeAll { $0.id == removed.id }
        }

        logPushStack()
    }

    /// Unified dismiss function that automatically determines what to dismiss
    func dismiss() {
        // Use full navigation history to determine what to dismiss
        guard !fullNavigationHistory.isEmpty else {
            print("🎯 Unified dismiss: nothing to dismiss (empty history)")
            return
        }
        
        // Get the last navigation item (most recent)
        guard let lastItem = fullNavigationHistory.last else {
            print("🎯 Unified dismiss: nothing to dismiss")
            return
        }
        
        print("🎯 Unified dismiss: dismissing \(lastItem.viewTypeName) [\(lastItem.type.rawValue)]")
        
        // Dismiss based on the type of the last navigation item
        switch lastItem.type {
        case .sheet, .fullscreen:
            dismissSheet()
        case .push:
            dismissPush()
        }
    }

    func dismissTo<T: View>(_ target: T.Type, dismissToMode: DismissToMode = .recent) {
        guard !fullNavigationHistory.isEmpty else {
            print("⚠️ Cannot dismissTo - navigation history is empty")
            return
        }
        
        let targetName = String(describing: target)
        print("🎯 Dismissing to \(targetName) with mode: \(dismissToMode)")
        print("📜 Current history: \(fullNavigationHistory.map { $0.viewTypeName })")
        
        var targetIndex: Int
        switch dismissToMode {
        case .root:
            guard let index = fullNavigationHistory.firstIndex(where: { $0.viewTypeName == targetName }) else {
                print("❌ Could not find \(targetName) in full history")
                return
            }
            targetIndex = index
        case .recent:
            // For recent, we want to find the most recent occurrence of the target
            // First, find all occurrences of the target
            let targetIndices = fullNavigationHistory.enumerated().compactMap { index, item in
                item.viewTypeName == targetName ? index : nil
            }
            
            guard !targetIndices.isEmpty else {
                print("❌ Could not find \(targetName) in full history")
                return
            }
            
            // If there's only one occurrence, we're already there
            if targetIndices.count == 1 {
                print("🎯 Only one occurrence of \(targetName) found - already at target")
                return
            }
            
            // Find the most recent occurrence
            let mostRecentIndex = targetIndices.last!
            
            // If we're already at the most recent occurrence, go to the previous one
            if mostRecentIndex == fullNavigationHistory.count - 1 {
                let previousIndex = targetIndices[targetIndices.count - 2]
                targetIndex = previousIndex
                print("🎯 Already at most recent \(targetName), going to previous at index \(previousIndex)")
            } else {
                targetIndex = mostRecentIndex
                print("🎯 Found most recent occurrence of \(targetName) at index \(mostRecentIndex)")
            }
        }
        
        let toRemove = fullNavigationHistory.suffix(from: targetIndex + 1)
        print("Will remove \(toRemove.count) items above target.")
        let count = toRemove.count
        for (index, item) in toRemove.reversed().enumerated() {
            switch item.location {
            case .rootPush(let idx):
                guard rootPushPath.indices.contains(idx) else { break }
                suppressedDismissIDs.insert(rootPushPath[idx].id)
                let removed = rootPushPath.remove(at: idx)
                if shouldCallOnDismiss(mode: .landing, index: index, count: count) {
                    print("Dismiss root push: \(removed.viewTypeName)")
                    removed.onDismiss?()
                }
            case .modalStack(let idx):
                guard modalStack.indices.contains(idx) else { break }
                let removed = modalStack.remove(at: idx)
                if shouldCallOnDismiss(mode: .landing, index: index, count: count) {
                    print("Dismiss modal: \(removed.id)")
                    removed.onDismiss?()
                }
                modalPushPaths[removed.id] = nil
            case .modalPush(let modalID, let pushIdx):
                guard var stack = modalPushPaths[modalID], stack.indices.contains(pushIdx) else { break }
                suppressedDismissIDs.insert(stack[pushIdx].id)
                let removed = stack.remove(at: pushIdx)
                if shouldCallOnDismiss(mode: .landing, index: index, count: count) {
                    print("Dismiss modal push: \(removed.viewTypeName)")
                    removed.onDismiss?()
                }
                modalPushPaths[modalID] = stack
            case .root:
                // Do nothing, root stays
                break
            }
        }
        fullNavigationHistory = Array(fullNavigationHistory.prefix(targetIndex + 1))
        print("→ Trimming fullNavigationHistory to index \(targetIndex)")
        print("=== End dismissTo ===\n")
    }

    private func shouldCallOnDismiss(mode: DismissalMode, index: Int, count: Int) -> Bool {
        switch mode {
        case .all:
            return true
        case .parent:
            return index == 0 // first in toRemove (topmost, direct parent)
        case .landing:
            return index == count - 1 // last in toRemove (landing view)
        }
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
    
    private func logPushStack() {
        if let modalID = modalStack.last?.id {
            print("📦 Push Stack [modal \(modalID.uuidString.prefix(4))]:")
            for ctx in modalPushPaths[modalID] ?? [] {
                print("• \(ctx.viewTypeName)")
            }
        } else {
            print("📦 Push Stack [root]:")
            for ctx in rootPushPath {
                print("• \(ctx.viewTypeName)")
            }
        }
    }
}
