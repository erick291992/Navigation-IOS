//
//  ModalStackHarness.swift
//  NavigationFrame3
//
//  Demo + UI-test harness for stacked modals. Every level shows its own @State
//  (counter, text, view-model instance id) and how many times .onAppear/.task fired,
//  so a remount is visible on screen.
//

import SwiftUI

/// Counts live outside the views so a remount can't reset them.
@Observable
final class HarnessLog {
    static let shared = HarnessLog()
    var appear: [String: Int] = [:]
    var task: [String: Int] = [:]
    var dismissed: [String] = []
}

@Observable
final class HarnessLevelViewModel {
    let instance = String(UUID().uuidString.prefix(6))
}

struct ModalStackHarnessRoot: View {
    @Environment(\.navigationManager) private var navigationManager

    var body: some View {
        VStack(spacing: 16) {
            Text("Modal stack harness").font(.title2.bold())
            HarnessStatus()
            Button("Present A (sheet)") { HarnessActions.presentA(navigationManager) }
                .accessibilityIdentifier("root.presentA")
            Button("Present A + B in one tap") {
                HarnessActions.presentA(navigationManager)
                HarnessActions.present(navigationManager, cover: false)
            }
            .accessibilityIdentifier("root.presentAB")
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }
}

/// Distinct type so `dismissTo(HarnessSheetA.self)` can target the first sheet.
struct HarnessSheetA: View {
    var body: some View { HarnessLevel(name: "A") }
}

struct HarnessLevel: View {
    let name: String
    @Environment(\.navigationManager) private var navigationManager
    @State private var viewModel = HarnessLevelViewModel()
    @State private var counter = 0
    @State private var text = ""
    @State private var showsInnerCoordinator = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Level \(name)").font(.title.bold())
                    .accessibilityIdentifier("\(name).title")
                Text(viewModel.instance).accessibilityIdentifier("\(name).vm")
                HStack {
                    Text("\(counter)").accessibilityIdentifier("\(name).counter")
                    Button("+1") { counter += 1 }.accessibilityIdentifier("\(name).inc")
                }
                TextField("Type here", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("\(name).field")
                HStack {
                    Text("appear \(HarnessLog.shared.appear[name, default: 0])")
                        .accessibilityIdentifier("\(name).appear")
                    Text("task \(HarnessLog.shared.task[name, default: 0])")
                        .accessibilityIdentifier("\(name).task")
                }
                HarnessStatus()
                actions
                if showsInnerCoordinator {
                    // A coordinator living inside this sheet, with its own manager
                    NavigationCoordinator(rootView: HarnessInnerRoot(), customKey: "harness-inner")
                        .frame(height: 120)
                }
            }
            .padding()
        }
        .onAppear { HarnessLog.shared.appear[name, default: 0] += 1 }
        .task { HarnessLog.shared.task[name, default: 0] += 1 }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            row("sheet", "Sheet") { HarnessActions.present(navigationManager, cover: false) }
            row("cover", "Full screen") { HarnessActions.present(navigationManager, cover: true) }
            row("swap", "Sheet (.swap)") { HarnessActions.present(navigationManager, cover: false, presentation: .swap) }
            row("push", "Push") { navigationManager.push { HarnessLevel(name: "\(name)-P") } }
            row("dismiss", "Dismiss sheet") { navigationManager.dismissSheet() }
            row("dismissToA", "Dismiss to A") { navigationManager.dismissTo(HarnessSheetA.self) }
            row("replaceLast", "Replace last") { HarnessActions.present(navigationManager, cover: false, style: .replaceLast) }
            row("replaceAll", "Replace all") { HarnessActions.present(navigationManager, cover: false, style: .replaceAll) }
            row("inner", "Embed inner coordinator") { showsInnerCoordinator = true }
        }
        .buttonStyle(.bordered)
    }

    private func row(_ id: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).accessibilityIdentifier("\(name).\(id)")
    }
}

/// Root of a coordinator embedded inside a harness sheet.
struct HarnessInnerRoot: View {
    @Environment(\.navigationManager) private var navigationManager

    var body: some View {
        Button("Inner sheet") {
            navigationManager.presentSheet { HarnessInnerSheet() }
        }
        .accessibilityIdentifier("inner.present")
    }
}

/// From inside the inner coordinator's sheet, asks the OUTER manager to stack a sheet.
struct HarnessInnerSheet: View {
    var body: some View {
        VStack {
            Text("Inner sheet").accessibilityIdentifier("inner.title")
            Button("Present on outer manager") {
                NavigationManagerRegistry.shared.manager(forCustomKey: "harness")?
                    .presentSheet { HarnessLevel(name: "B") }
            }
            .accessibilityIdentifier("inner.presentOuter")
            Text("outer stack \(NavigationManagerRegistry.shared.manager(forCustomKey: "harness")?.modalStack.count ?? -1)")
                .accessibilityIdentifier("inner.outerCount")
        }
    }
}

struct HarnessStatus: View {
    @Environment(\.navigationManager) private var navigationManager

    var body: some View {
        VStack {
            Text("stack \(navigationManager.modalStack.count)")
                .accessibilityIdentifier("stack.count")
            Text("dismissed \(HarnessLog.shared.dismissed.joined(separator: ","))")
                .accessibilityIdentifier("dismissed.log")
        }
        .font(.caption.monospaced())
    }
}

enum HarnessActions {
    static func presentA(_ manager: NavigationManager) {
        manager.presentSheet(view: { HarnessSheetA() }, onDismiss: { HarnessLog.shared.dismissed.append("A") })
    }

    /// Names levels by stack position after the call: A, B, C, D…
    static func present(
        _ manager: NavigationManager,
        cover: Bool,
        style: NavigationManager.SheetPresentationStyle = .stack,
        presentation: NavigationManager.ModalPresentationMode? = nil
    ) {
        let count = manager.modalStack.count
        let index = switch style {
        case .stack: count
        case .replaceLast: max(count - 1, 0)
        case .replaceAll: 0
        }
        let name = String(UnicodeScalar(UInt8(65 + index)))
        let onDismiss = { HarnessLog.shared.dismissed.append(name) }
        if cover {
            manager.presentFullScreen(style: style, presentation: presentation, view: { HarnessLevel(name: name) }, onDismiss: onDismiss)
        } else {
            manager.presentSheet(style: style, presentation: presentation, view: { HarnessLevel(name: name) }, onDismiss: onDismiss)
        }
    }
}
