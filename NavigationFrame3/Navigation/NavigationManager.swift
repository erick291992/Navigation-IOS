//
//  NavigationManager.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

@Observable
final class NavigationManager {
    enum LogLevel: Int {
        case none = 0, error = 1, info = 2, debug = 3
    }
    
    var logLevel: LogLevel = .error

    var modalStack: [ModalContext] = []
    var fullNavigationHistory: [NavigationItem] = []

    // ✅ onDismiss triggered when views are popped from root stack
    var rootPushPath: [PushContext] = [] {
        didSet {
            guard oldValue.count > rootPushPath.count else { return }
            let removed = oldValue.suffix(from: rootPushPath.count)
            for context in removed {
                if suppressedDismissIDs.contains(context.id) {
                    log("🚫 Suppressed native pop: \(context.viewTypeName)", level: .debug)
                    suppressedDismissIDs.remove(context.id)
                } else {
                    log("🔥 Native pop: \(context.viewTypeName) [root]", level: .info)
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
        case topmost    // Only call onDismiss for the topmost (currently visible) view being removed
    }

    enum DismissToMode {
        case root      // Go to the first occurrence (root)
        case recent    // Go to the most recent occurrence
    }

    func log(_ message: String, level: LogLevel) {
        guard level.rawValue <= logLevel.rawValue else { return }
        print(message)
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
                log("📦 Pushed view of type \(context.viewTypeName) [context: modal \(modalID.uuidString.prefix(4))]", level: .info)
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
                log("⚠️ Tried to push into modal \(modalID.uuidString.prefix(4)), but it's no longer mounted. Falling back to root.", level: .info)
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
            log("📦 Pushed view of type \(context.viewTypeName) [context: root]", level: .info)
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
                log("🔥 Replacing last modal: \(removed.id.uuidString.prefix(4))", level: .info)
                removed.onDismiss?()
                modalPushPaths[removed.id] = nil
            }

        case .replaceAll:
            for context in modalStack.reversed() {
                log("🔥 Replacing all → dismissing modal: \(context.id.uuidString.prefix(4))", level: .info)
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
            log("🆕 Initializing push path for modal \(context.id.uuidString.prefix(4))", level: .info)
            modalPushPaths[context.id] = []
        } else {
            log("♻️ Reusing existing push path for modal \(context.id.uuidString.prefix(4))", level: .info)
        }

        let index = modalStack.count
        modalStack.append(context)

        log("📝 Adding modal to stack: \(context.id) at index \(index)", level: .info)
        log("📝 Modal stack count after adding: \(modalStack.count)", level: .info)

        fullNavigationHistory.append(
            NavigationItem(
                id: context.id,
                viewTypeName: String(describing: Content.self),
                type: .sheet,
                location: .modalStack(index: index)
            )
        )

        log("🎯 Presented sheet \(context.id) of type \(Content.self)", level: .info)
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
                log("🔥 Replacing last modal: \(removed.id.uuidString.prefix(4))", level: .info)
                removed.onDismiss?()
                modalPushPaths[removed.id] = nil
            }

        case .replaceAll:
            for context in modalStack.reversed() {
                log("🔥 Replacing all → dismissing modal: \(context.id.uuidString.prefix(4))", level: .info)
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
            log("🆕 Initializing push path for modal \(context.id.uuidString.prefix(4))", level: .info)
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

        log("🎯 Presented fullScreenCover \(context.id) of type \(Content.self)", level: .info)
        logModalStack()
    }

    func dismissSheet(dismissalMode: DismissalMode = .topmost) {
        guard let removed = modalStack.popLast() else { return }

        let removedID = removed.id
        log("❎ Dismissed sheet \(removedID) with dismissalMode: \(dismissalMode)", level: .info)

        // Check if there are pushed views BEFORE processing them
        let hasPushedViews = !(modalPushPaths[removedID]?.isEmpty ?? true)

        // ✅ Trigger onDismiss for pushed views in the dismissed sheet based on dismissalMode
        if let removedStack = modalPushPaths[removedID] {
            let count = removedStack.count
            // Only run the loop for .all or .topmost (not .landing)
            if dismissalMode == .all || dismissalMode == .topmost {
                for (index, context) in removedStack.reversed().enumerated() {
                    if shouldCallOnDismiss(mode: dismissalMode, index: index, count: count) {
                        log("🔥 Native pop: \(context.viewTypeName) [modal \(removedID.uuidString.prefix(4))]", level: .info)
                        context.onDismiss?()
                    }
                }
            }
            // For .landing, do nothing here (only the sheet root's onDismiss will be called below)
        }

        // ✅ Remove push path only for the dismissed modal
        modalPushPaths[removedID] = nil

        // ✅ Trigger modal-level onDismiss based on dismissalMode
        switch dismissalMode {
        case .all, .landing:
            // Call sheet's root onDismiss for .all and .landing
            removed.onDismiss?()
        case .topmost:
            // For .topmost, call sheet's root onDismiss ONLY if there are no pushed views
            if !hasPushedViews {
                removed.onDismiss?()
            }
        }

        // �� Re-log modal stack for visibility
        logModalStack()
    }

    func dismissPush() {
        // Check if a modal is active
        if let modalID = modalStack.last?.id {
            guard var currentStack = modalPushPaths[modalID], !currentStack.isEmpty else { return }
            
            let removed = currentStack.removeLast()
            log("❎ Dismissed pushed view: \(removed.viewTypeName) [modal \(modalID.uuidString.prefix(4))]", level: .info)
            removed.onDismiss?()

            updateModalPushPath(for: modalID, newValue: currentStack)
            
            // Also remove from full navigation history
            fullNavigationHistory.removeAll { $0.id == removed.id }

        } else {
            // Otherwise, dismiss from root push stack
            guard !rootPushPath.isEmpty else { return }

            let removed = rootPushPath.removeLast()
            log("❎ Dismissed pushed view: \(removed.viewTypeName) [root]", level: .info)
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
            log("🎯 Unified dismiss: nothing to dismiss (empty history)", level: .info)
            return
        }
        
        // Get the last navigation item (most recent)
        guard let lastItem = fullNavigationHistory.last else {
            log("🎯 Unified dismiss: nothing to dismiss", level: .info)
            return
        }
        
        log("🎯 Unified dismiss: dismissing \(lastItem.viewTypeName) [\(lastItem.type.rawValue)]", level: .info)
        
        // Dismiss based on the type of the last navigation item
        switch lastItem.type {
        case .sheet, .fullscreen:
            dismissSheet()
        case .push:
            dismissPush()
        }
    }

    func dismissTo<T: View>(_ target: T.Type, dismissToMode: DismissToMode = .recent, dismissalMode: DismissalMode = .topmost) {
        guard !fullNavigationHistory.isEmpty else {
            log("⚠️ Cannot dismissTo - navigation history is empty", level: .error)
            return
        }
        
        let targetName = String(describing: target)
        log("🎯 Dismissing to \(targetName) with mode: \(dismissToMode), dismissalMode: \(dismissalMode)", level: .info)
        log("📜 Current history: \(fullNavigationHistory.map { $0.viewTypeName })", level: .debug)
        
        var targetIndex: Int
        switch dismissToMode {
        case .root:
            // For root, we want to find the first occurrence of the target
            guard let index = fullNavigationHistory.firstIndex(where: { $0.viewTypeName == targetName }) else {
                log("❌ Could not find \(targetName) in full history", level: .error)
                return
            }
            targetIndex = index
            log("🎯 Found first occurrence of \(targetName) at index \(index)", level: .info)
            
        case .recent:
            // For recent, we want to find the most recent occurrence of the target
            // First, find all occurrences of the target
            let targetIndices = fullNavigationHistory.enumerated().compactMap { index, item in
                item.viewTypeName == targetName ? index : nil
            }
            
            guard !targetIndices.isEmpty else {
                log("❌ Could not find \(targetName) in full history", level: .error)
                return
            }
            
            // Find the most recent occurrence
            let mostRecentIndex = targetIndices.last!
            
            // If there's only one occurrence and we're not at it, go to it
            if targetIndices.count == 1 && mostRecentIndex != fullNavigationHistory.count - 1 {
                targetIndex = mostRecentIndex
                log("🎯 Only one occurrence of \(targetName) found at index \(mostRecentIndex) - going to it", level: .info)
            }
            // If there's only one occurrence and we're already at it, do nothing
            else if targetIndices.count == 1 && mostRecentIndex == fullNavigationHistory.count - 1 {
                log("🎯 Only one occurrence of \(targetName) found - already at target", level: .info)
                return
            }
            // If there are multiple occurrences and we're at the most recent, go to the previous one
            else if mostRecentIndex == fullNavigationHistory.count - 1 {
                let previousIndex = targetIndices[targetIndices.count - 2]
                targetIndex = previousIndex
                log("🎯 Already at most recent \(targetName), going to previous at index \(previousIndex)", level: .info)
            }
            // Otherwise, go to the most recent occurrence
            else {
                targetIndex = mostRecentIndex
                log("🎯 Found most recent occurrence of \(targetName) at index \(mostRecentIndex)", level: .info)
            }
        }
        
        let toRemove = fullNavigationHistory.suffix(from: targetIndex + 1)
        log("Will remove \(toRemove.count) items above target.", level: .info)
        let count = toRemove.count
        for (index, item) in toRemove.reversed().enumerated() {
            switch item.location {
            case .rootPush(let idx):
                guard rootPushPath.indices.contains(idx) else { break }
                suppressedDismissIDs.insert(rootPushPath[idx].id)
                let removed = rootPushPath.remove(at: idx)
                if shouldCallOnDismiss(mode: dismissalMode, index: index, count: count) {
                    log("Dismiss root push: \(removed.viewTypeName)", level: .info)
                    removed.onDismiss?()
                }
            case .modalStack(let idx):
                guard modalStack.indices.contains(idx) else { break }
                let removed = modalStack.remove(at: idx)
                if shouldCallOnDismiss(mode: dismissalMode, index: index, count: count) {
                    log("Dismiss modal: \(removed.id)", level: .info)
                    removed.onDismiss?()
                }
                modalPushPaths[removed.id] = nil
            case .modalPush(let modalID, let pushIdx):
                guard var stack = modalPushPaths[modalID], stack.indices.contains(pushIdx) else { break }
                suppressedDismissIDs.insert(stack[pushIdx].id)
                let removed = stack.remove(at: pushIdx)
                if shouldCallOnDismiss(mode: dismissalMode, index: index, count: count) {
                    log("Dismiss modal push: \(removed.viewTypeName)", level: .info)
                    removed.onDismiss?()
                }
                modalPushPaths[modalID] = stack
            case .root:
                // Do nothing, root stays
                break
            }
        }
        fullNavigationHistory = Array(fullNavigationHistory.prefix(targetIndex + 1))
        log("→ Trimming fullNavigationHistory to index \(targetIndex)", level: .debug)
        log("=== End dismissTo ===", level: .debug)
    }

    private func shouldCallOnDismiss(mode: DismissalMode, index: Int, count: Int) -> Bool {
        switch mode {
        case .all:
            return true
        case .topmost:
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
                log("🔥 Native pop: \(context.viewTypeName) [modal \(modalID.uuidString.prefix(4))]", level: .info)
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
        log("🧼 NavigationManager fully reset", level: .info)
    }

    private func logModalStack() {
        log("🧱 Modal Stack:", level: .debug)
        for context in modalStack {
            log("• \(context.id)", level: .debug)
        }
    }
    
    private func logPushStack() {
        if let modalID = modalStack.last?.id {
            log("📦 Push Stack [modal \(modalID.uuidString.prefix(4))]:", level: .debug)
            for ctx in modalPushPaths[modalID] ?? [] {
                log("• \(ctx.viewTypeName)", level: .debug)
            }
        } else {
            log("📦 Push Stack [root]:", level: .debug)
            for ctx in rootPushPath {
                log("• \(ctx.viewTypeName)", level: .debug)
            }
        }
    }
}
