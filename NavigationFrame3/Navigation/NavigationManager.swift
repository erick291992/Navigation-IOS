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
        
        /// Default log level based on build configuration
        /// Computed once at compile time - same value for all instances
        static var `default`: LogLevel {
            #if DEBUG
            return .info
            #else
            return .none
            #endif
        }
    }
    
    #if DEBUG
    var logLevel: LogLevel = .info
    #else
    var logLevel: LogLevel = .none
    #endif
    var defaultDismissalMode: DismissalMode = .all
    var defaultSheetDismissalMode: DismissalMode = .all
    var defaultDismissToMode: DismissToMode = .recent
    var defaultModalPresentationMode: ModalPresentationMode = .swap

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
                    fullNavigationHistory.removeAll { $0.id == context.id }
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

    /// How a new modal appears relative to the one below it. Visual only:
    /// `modalStack` holds every modal either way.
    enum ModalPresentationMode {
        case swap      // 🔀 Lower modal slides away (and is rebuilt fresh when uncovered)
        case stacked   // 🃏 Lower modal stays mounted underneath, state intact
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
                log("⚠️ Tried to push into modal \(modalID.uuidString.prefix(4)), but it's no longer mounted. Falling back to root.", level: .error)
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
        presentation: ModalPresentationMode? = nil,
        detents: Set<PresentationDetent>? = nil,
        dragIndicator: Visibility? = nil,
        @ViewBuilder view: @escaping () -> Content,
        onDismiss: (() -> Void)? = nil
    ) {
        applyReplacement(style)

        let presentationOptions = (detents != nil || dragIndicator != nil) 
            ? SheetPresentationOptions(detents: detents, dragIndicator: dragIndicator)
            : nil

        let context = ModalContext(
            style: .sheet,
            presentation: presentation ?? defaultModalPresentationMode,
            sheetPresentationOptions: presentationOptions,
            makeView: { AnyView(view()) },
            onDismiss: onDismiss
        )
        appendModal(context, viewTypeName: String(describing: Content.self), type: .sheet)
        log("🎯 Presented sheet \(context.id) of type \(Content.self)", level: .info)
        logModalStack()
    }

    func presentFullScreen<Content: View>(
        style: SheetPresentationStyle = .stack,
        presentation: ModalPresentationMode? = nil,
        @ViewBuilder view: @escaping () -> Content,
        onDismiss: (() -> Void)? = nil
    ) {
        applyReplacement(style)

        let context = ModalContext(
            style: .fullScreen,
            presentation: presentation ?? defaultModalPresentationMode,
            makeView: view,
            onDismiss: onDismiss
        )
        appendModal(context, viewTypeName: String(describing: Content.self), type: .fullscreen)
        log("🎯 Presented fullScreenCover \(context.id) of type \(Content.self)", level: .info)
        logModalStack()
    }

    private func applyReplacement(_ style: SheetPresentationStyle) {
        switch style {
        case .replaceLast:
            log("🔥 Replacing last modal", level: .info)
            removeModals(from: modalStack.count - 1, mode: defaultSheetDismissalMode)
        case .replaceAll:
            log("🔥 Replacing all modals", level: .info)
            removeModals(from: 0, mode: defaultSheetDismissalMode)
        case .stack:
            break // Default: allow stacking
        }
    }

    private func appendModal(_ context: ModalContext, viewTypeName: String, type: NavigationItem.NavigationType) {
        modalPushPaths[context.id] = []
        let index = modalStack.count
        modalStack.append(context)
        log("📝 Adding modal to stack: \(context.id) at index \(index) [\(context.presentation)]", level: .debug)

        fullNavigationHistory.append(
            NavigationItem(
                id: context.id,
                viewTypeName: viewTypeName,
                type: type,
                location: .modalStack(index: index)
            )
        )
    }

    /// The modal presented directly by `parentID`'s container (`nil` = the coordinator root).
    ///
    /// Modals are grouped into "rungs": a `.stacked` modal starts a new rung, a `.swap`
    /// modal takes over the rung of the modal before it. Each rung shows its newest
    /// member, and each rung's container presents the next rung.
    func childModal(of parentID: UUID?) -> ModalContext? {
        var visible: [ModalContext] = []
        for context in modalStack {
            if context.presentation == .swap, !visible.isEmpty {
                visible[visible.count - 1] = context
            } else {
                visible.append(context)
            }
        }
        guard let parentID else { return visible.first }
        guard let index = visible.firstIndex(where: { $0.id == parentID }), index + 1 < visible.count else { return nil }
        return visible[index + 1]
    }

    func dismissSheet(dismissalMode: DismissalMode? = nil) {
        removeModals(from: modalStack.count - 1, mode: dismissalMode ?? defaultSheetDismissalMode)
    }

    /// Dismisses the modal with `id` and every modal above it. No-op if it's already gone,
    /// so it's safe to call from several presentation bindings for the same dismissal.
    func dismissModal(id: UUID, dismissalMode: DismissalMode? = nil) {
        guard let index = modalStack.firstIndex(where: { $0.id == id }) else { return }
        removeModals(from: index, mode: dismissalMode ?? defaultSheetDismissalMode)
    }

    /// Single removal path for modals: drops `modalStack[index...]`, their push paths and
    /// history, then calls onDismiss (topmost first) according to `mode`.
    private func removeModals(from index: Int, mode: DismissalMode) {
        guard modalStack.indices.contains(index) else { return }

        let removed = Array(modalStack[index...])
        modalStack.removeSubrange(index...)

        // Topmost first: each modal's pushes (top → bottom), then the modal itself
        var dismissals: [(name: String, onDismiss: (() -> Void)?)] = []
        for context in removed.reversed() {
            for push in (modalPushPaths[context.id] ?? []).reversed() {
                dismissals.append(("\(push.viewTypeName) [modal \(context.id.uuidString.prefix(4))]", push.onDismiss))
            }
            dismissals.append(("modal \(context.id.uuidString.prefix(4))", context.onDismiss))
        }

        let removedIDs = Set(removed.map(\.id))
        for id in removedIDs { modalPushPaths[id] = nil }
        fullNavigationHistory.removeAll { item in
            if removedIDs.contains(item.id) { return true }
            if case .modalPush(let modalID, _) = item.location { return removedIDs.contains(modalID) }
            return false
        }

        log("❎ Dismissed \(removed.count) modal(s) with dismissalMode: \(mode)", level: .info)
        for (index, dismissal) in dismissals.enumerated() where shouldCallOnDismiss(mode: mode, index: index, count: dismissals.count) {
            log("🔥 onDismiss: \(dismissal.name)", level: .info)
            dismissal.onDismiss?()
        }

        logModalStack()
    }

    func dismissPush() {
        // Check if a modal is active
        if let modalID = modalStack.last?.id {
            guard var currentStack = modalPushPaths[modalID], !currentStack.isEmpty else { return }
            
            let removed = currentStack.removeLast()
            log("❎ Dismissed pushed view: \(removed.viewTypeName) [modal \(modalID.uuidString.prefix(4))]", level: .info)
            removed.onDismiss?()

            // Directly update the path without triggering updateModalPushPath
            // since we're doing manual dismissal, not detecting native dismissal
            modalPushPaths[modalID] = currentStack
            
            // Also remove from full navigation history
            fullNavigationHistory.removeAll { $0.id == removed.id }

        } else {
            // Otherwise, dismiss from root push stack
            guard !rootPushPath.isEmpty else { return }

            // Add to suppressed IDs BEFORE removing to prevent didSet from triggering onDismiss
            let removedID = rootPushPath.last!.id
            suppressedDismissIDs.insert(removedID)
            
            let removed = rootPushPath.removeLast()
            log("❎ Dismissed pushed view: \(removed.viewTypeName) [root]", level: .info)
            removed.onDismiss?()

            // rootPushPath is already updated by removeLast(), no need to reassign
            // This prevents triggering SwiftUI's native dismissal detection

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
            dismissSheet() // Uses defaultDismissalMode
        case .push:
            dismissPush()
        }
    }

    /// Intelligent dismiss function that goes back to the previous logical view
    func dismissBack() {
        guard !fullNavigationHistory.isEmpty else {
            log("🎯 DismissBack: nothing to dismiss (empty history)", level: .info)
            return
        }
        
        // If we only have the root view, we can't go back
        if fullNavigationHistory.count == 1 {
            log("🎯 DismissBack: already at root, nothing to dismiss", level: .info)
            return
        }
        
        // Find the previous view in the history
        let previousIndex = fullNavigationHistory.count - 2
        let previousItem = fullNavigationHistory[previousIndex]
        let previousViewType = previousItem.viewTypeName
        
        log("🎯 DismissBack: going back to \(previousViewType)", level: .info)
        
        // Use dismissTo to go back to the previous view
        // We need to use the actual type, so we'll use a different approach
        dismissToPreviousView()
    }
    
    /// Dismiss everything after the previous view to go back to it
    private func dismissToPreviousView() {
        guard fullNavigationHistory.count > 1 else {
            log("🎯 DismissToPreviousView: already at root", level: .info)
            return
        }
        
        // Find the target index (previous view)
        let targetIndex = fullNavigationHistory.count - 2
        
        // Get all items to remove (everything after the target)
        let toRemove = fullNavigationHistory.suffix(from: targetIndex + 1)
        log("🎯 DismissToPreviousView: removing \(toRemove.count) items to go back to \(fullNavigationHistory[targetIndex].viewTypeName)", level: .info)
        
        // Remove items in reverse order (from newest to oldest)
        for item in toRemove.reversed() {
            log("🎯 DismissToPreviousView: removing \(item.viewTypeName) [\(item.type.rawValue)]", level: .info)
            
            // Dismiss the item based on its location
            switch item.location {
            case .rootPush:
                guard let idx = rootPushPath.firstIndex(where: { $0.id == item.id }) else { break }
                
                // Add to suppressed IDs BEFORE removing to prevent didSet from triggering onDismiss
                suppressedDismissIDs.insert(item.id)
                
                let removed = rootPushPath.remove(at: idx)
                log("❎ Dismissed pushed view: \(removed.viewTypeName) [root]", level: .info)
                removed.onDismiss?()
                
            case .modalStack:
                guard let idx = modalStack.firstIndex(where: { $0.id == item.id }) else { break }
                let removed = modalStack.remove(at: idx)
                log("❎ Dismissed modal: \(removed.id)", level: .info)
                removed.onDismiss?()
                modalPushPaths[removed.id] = nil
                
            case .modalPush(let modalID, _):
                guard var stack = modalPushPaths[modalID], let pushIdx = stack.firstIndex(where: { $0.id == item.id }) else { break }
                
                // Direct write below bypasses updateModalPushPath, so no native-pop onDismiss fires
                let removed = stack.remove(at: pushIdx)
                log("❎ Dismissed pushed view: \(removed.viewTypeName) [modal \(modalID.uuidString.prefix(4))]", level: .info)
                removed.onDismiss?()
                modalPushPaths[modalID] = stack
                
            case .root:
                // Root stays, do nothing
                break
            }
        }
        
        // Trim the history to the target index
        fullNavigationHistory = Array(fullNavigationHistory.prefix(targetIndex + 1))
        
        log("🎯 DismissToPreviousView: now at \(fullNavigationHistory.last?.viewTypeName ?? "unknown")", level: .info)
    }

    func dismissTo<T: View>(_ target: T.Type, dismissToMode: DismissToMode? = nil, dismissalMode: DismissalMode? = nil) {
        let toMode = dismissToMode ?? defaultDismissToMode
        let disMode = dismissalMode ?? defaultDismissalMode
        
        guard !fullNavigationHistory.isEmpty else {
            log("⚠️ Cannot dismissTo - navigation history is empty", level: .error)
            return
        }
        
        let targetName = String(describing: target)
        log("🎯 Dismissing to \(targetName) with mode: \(toMode), dismissalMode: \(disMode)", level: .info)
        log("📜 Current history: \(fullNavigationHistory.map { $0.viewTypeName })", level: .debug)
        
        var targetIndex: Int
        switch toMode {
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
            case .rootPush:
                guard let idx = rootPushPath.firstIndex(where: { $0.id == item.id }) else { break }
                suppressedDismissIDs.insert(item.id)
                let removed = rootPushPath.remove(at: idx)
                if shouldCallOnDismiss(mode: disMode, index: index, count: count) {
                    log("Dismiss root push: \(removed.viewTypeName)", level: .info)
                    removed.onDismiss?()
                }
            case .modalStack:
                guard let idx = modalStack.firstIndex(where: { $0.id == item.id }) else { break }
                let removed = modalStack.remove(at: idx)
                if shouldCallOnDismiss(mode: disMode, index: index, count: count) {
                    log("Dismiss modal: \(removed.id)", level: .info)
                    removed.onDismiss?()
                }
                modalPushPaths[removed.id] = nil
            case .modalPush(let modalID, _):
                guard var stack = modalPushPaths[modalID], let pushIdx = stack.firstIndex(where: { $0.id == item.id }) else { break }
                let removed = stack.remove(at: pushIdx)
                if shouldCallOnDismiss(mode: disMode, index: index, count: count) {
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
                fullNavigationHistory.removeAll { $0.id == context.id }
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
