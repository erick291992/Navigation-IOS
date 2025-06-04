//
//  NavigationManager.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

final class NavigationManager: ObservableObject {
    static let shared = NavigationManager()
    var rootViewTypeName: String?

    @Published var pushPath: [NavigationItem] = []
    @Published var modalStack: [ModalContext] = []
    @Published var fullNavigationHistory: [NavigationItem] = []
    

    struct ModalContext: Identifiable, Hashable {
        let id = UUID()
        var root: NavigationItem
        var pushPath: [NavigationItem] = []
        var type: NavigationItem.NavigationType

        static func == (lhs: ModalContext, rhs: ModalContext) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    // MARK: - Current Push Stack Binding
    private var currentPushBinding: Binding<[NavigationItem]> {
        if modalStack.isEmpty {
            return Binding(
                get: { self.pushPath },
                set: { self.pushPath = $0 }
            )
        } else {
            let lastIndex = modalStack.count - 1
            return Binding(
                get: { self.modalStack[lastIndex].pushPath },
                set: { newValue in
                    var modal = self.modalStack[lastIndex]
                    modal.pushPath = newValue
                    self.modalStack[lastIndex] = modal // <- 🔥 this triggers SwiftUI
                }
            )
        }
    }



    // MARK: - API
    func push<Content: View>(view: @escaping () -> Content) {
        let typeName = String(describing: Content.self)
        let item = NavigationItem(
            viewFactory: { AnyView(view()) },
            type: .push,
            viewTypeName: typeName
        )
        currentPushBinding.wrappedValue.append(item)
        fullNavigationHistory.append(item)
        logStacks("📦 PUSH \(typeName)")
    }


    func presentSheet<Content: View>(view: @escaping () -> Content) {
        let container = NavigationContainerView { view() }
        let typeName = String(describing: Content.self)
        let rootItem = NavigationItem(
            viewFactory: { AnyView(container) },
            type: .sheet,
            viewTypeName: typeName
        )
        let modal = ModalContext(root: rootItem, type: .sheet)
        modalStack.append(modal)
        fullNavigationHistory.append(rootItem)
        logStacks("🪟 SHEET \(typeName)")
    }


    func presentFullscreen<Content: View>(view: @escaping () -> Content) {
        let typeName = String(describing: Content.self)
        let container = NavigationContainerView {
            view()
        }
        let rootItem = NavigationItem(viewFactory: { AnyView(container) }, type: .fullscreen, viewTypeName: typeName)
        let modal = ModalContext(root: rootItem, type: .fullscreen)
        modalStack.append(modal)
        fullNavigationHistory.append(rootItem)
        logStacks("🧊 FULLSCREEN \(rootItem.typeName)")
    }

    func pop() {
        if modalStack.isEmpty {
            if !pushPath.isEmpty {
                pushPath.removeLast()
                logStacks("🔙 POP")
            }
        } else if !modalStack.last!.pushPath.isEmpty {
            modalStack[modalStack.count - 1].pushPath.removeLast()
            logStacks("🔙 POP (modal)")
        }
    }

    func popTo(index: Int) {
        currentPushBinding.wrappedValue = Array(currentPushBinding.wrappedValue.prefix(index + 1))
        logStacks("⏪ POP TO INDEX \(index)")
    }

    func dismissTopModal() {
        if !modalStack.isEmpty {
            modalStack.removeLast()
            logStacks("❎ DISMISS TOP MODAL")
        }
    }

    func dismissAllModals() {
        modalStack.removeAll()
        logStacks("🧹 DISMISS ALL MODALS")
    }

    func popOrDismiss() {
        if modalStack.last?.pushPath.isEmpty == false {
            pop()
        } else if !modalStack.isEmpty {
            dismissTopModal()
        } else {
            pop()
        }
    }

    func dismissTo<Content: View>(_ viewType: Content.Type) {
        let target = String(describing: viewType)

        // 1. Search modal pushPaths
        for (i, modal) in modalStack.enumerated().reversed() {
            if let index = modal.pushPath.lastIndex(where: { $0.viewTypeName == target }) {
                modalStack = Array(modalStack.prefix(i + 1))
                modalStack[modalStack.count - 1].pushPath = Array(modalStack.last!.pushPath.prefix(index + 1))
                logStacks("🎯 DISMISS TO \(target) (modal pushPath)")
                return
            }
        }

        // 2. Search modal root items
        if let index = modalStack.lastIndex(where: { $0.root.viewTypeName == target }) {
            modalStack = Array(modalStack.prefix(index + 1))
            modalStack[index].pushPath = []
            logStacks("🎯 DISMISS TO \(target) (modal root)")
            return
        }

        // 3. Search root pushPath
        if let index = pushPath.lastIndex(where: { $0.viewTypeName == target }) {
            dismissAllModals()
            pushPath = Array(pushPath.prefix(index + 1))
            logStacks("🎯 DISMISS TO \(target) (root pushPath)")
            return
        }

        // 4. Handle root root view (ContentView)
        if let rootType = rootViewTypeName, target == rootType {
            dismissAllModals()
            pushPath.removeAll()
            logStacks("🎯 DISMISS TO ROOT VIEW (\(target))")
        }

    }



    // MARK: - Debug Logs
    private func logStacks(_ label: String) {
        print("""
        === \(label) ===
        🧱 Root Stack: \(pushPath.map(\.typeName))
        🪟 Modal Stack:
        \(modalStack.map {
            "• \($0.type.rawValue.uppercased()) root: \($0.root.typeName), pushPath: \($0.pushPath.map(\.typeName))"
        }.joined(separator: "\n"))
        📜 Full History: \(fullNavigationHistory.map(\.typeName))
        ====================
        """)
    }
}
