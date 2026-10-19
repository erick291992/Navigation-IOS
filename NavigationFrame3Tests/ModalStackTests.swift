//
//  ModalStackTests.swift
//  NavigationFrame3Tests
//

import Testing
import SwiftUI
@testable import NavigationFrame3

private struct A: View { var body: some View { Text("A") } }
private struct B: View { var body: some View { Text("B") } }
private struct C: View { var body: some View { Text("C") } }
private struct D: View { var body: some View { Text("D") } }
private struct P: View { var body: some View { Text("P") } }

/// Records onDismiss calls in order.
private final class Log {
    var calls: [String] = []
    func on(_ name: String) -> () -> Void { { self.calls.append(name) } }
}

private func makeManager(mode: NavigationManager.DismissalMode = .all) -> NavigationManager {
    let manager = NavigationManager()
    manager.logLevel = .none
    manager.defaultDismissalMode = mode
    manager.defaultSheetDismissalMode = mode
    return manager
}

/// Presents A → B → C as sheets, each with one pushed view (A.p, B.p, C.p).
private func stackABC(_ m: NavigationManager, _ log: Log, withPushes: Bool = true,
                      presentation: NavigationManager.ModalPresentationMode? = nil) {
    for name in ["A", "B", "C"] {
        m.presentSheet(presentation: presentation, view: { Text(name) }, onDismiss: log.on(name))
        if withPushes { m.push(view: { P() }, onDismiss: log.on("\(name).p")) }
    }
}

struct DismissSheetTests {
    @Test(arguments: [
        (NavigationManager.DismissalMode.all, true, ["C.p", "C"]),
        (.topmost, true, ["C.p"]),
        (.landing, true, ["C"]),
        (.all, false, ["C"]),
        (.topmost, false, ["C"]),
        (.landing, false, ["C"]),
    ])
    func dismissSheetHonorsMode(mode: NavigationManager.DismissalMode, withPushes: Bool, expected: [String]) {
        let m = makeManager(mode: mode), log = Log()
        stackABC(m, log, withPushes: withPushes)
        m.dismissSheet()
        #expect(log.calls == expected)
        #expect(m.modalStack.count == 2)
    }

    @Test func dismissSheetTrimsHistory() {
        let m = makeManager(), log = Log()
        stackABC(m, log)
        let cID = m.modalStack[2].id
        m.dismissSheet()
        #expect(!m.fullNavigationHistory.contains { $0.id == cID })
        #expect(m.modalPushPaths[cID] == nil)
        // dismiss() after dismissSheet() must target B's push, not pop another sheet
        m.dismiss()
        #expect(m.modalStack.count == 2)
        #expect(m.modalPushPaths[m.modalStack[1].id]?.isEmpty == true)
    }
}

struct DismissModalTests {
    @Test(arguments: [
        (NavigationManager.DismissalMode.all, ["C.p", "C", "B.p", "B"]),
        (.topmost, ["C.p"]),
        (.landing, ["B"]),
    ])
    func dismissMiddleRemovesItAndAbove(mode: NavigationManager.DismissalMode, expected: [String]) {
        let m = makeManager(mode: mode), log = Log()
        stackABC(m, log)
        let a = m.modalStack[0]
        m.dismissModal(id: m.modalStack[1].id)
        #expect(m.modalStack.map(\.id) == [a.id])
        #expect(log.calls == expected)
    }

    @Test func dismissModalIsIdempotent() {
        let m = makeManager(), log = Log()
        stackABC(m, log)
        let bID = m.modalStack[1].id
        m.dismissModal(id: bID)
        let after = log.calls
        m.dismissModal(id: bID)
        m.dismissModal(id: UUID())
        #expect(log.calls == after)
        #expect(m.modalStack.count == 1)
    }

    @Test func historyIsTrimmedForRemovedModalsAndTheirPushes() {
        let m = makeManager(), log = Log()
        stackABC(m, log)
        m.dismissModal(id: m.modalStack[1].id)
        // A + A.p (no coordinator root in unit tests)
        #expect(m.fullNavigationHistory.count == 2)
    }

    @Test func onDismissSeesConsistentState() {
        let m = makeManager()
        var countSeenInCallback = -1
        m.presentSheet(view: { A() })
        m.presentSheet(view: { B() }, onDismiss: { countSeenInCallback = m.modalStack.count })
        m.dismissSheet()
        #expect(countSeenInCallback == 1)
    }
}

struct ReplaceStyleTests {
    @Test(arguments: [
        (NavigationManager.DismissalMode.all, ["C.p", "C"]),
        (.topmost, ["C.p"]),
        (.landing, ["C"]),
    ])
    func replaceLastHonorsMode(mode: NavigationManager.DismissalMode, expected: [String]) {
        let m = makeManager(mode: mode), log = Log()
        stackABC(m, log)
        let ab = m.modalStack.prefix(2).map(\.id)
        m.presentSheet(style: .replaceLast) { D() }
        #expect(log.calls == expected)
        #expect(Array(m.modalStack.prefix(2).map(\.id)) == ab)
        #expect(m.modalStack.count == 3)
    }

    @Test(arguments: [
        (NavigationManager.DismissalMode.all, ["C.p", "C", "B.p", "B", "A.p", "A"]),
        (.topmost, ["C.p"]),
        (.landing, ["A"]),
    ])
    func replaceAllHonorsMode(mode: NavigationManager.DismissalMode, expected: [String]) {
        let m = makeManager(mode: mode), log = Log()
        stackABC(m, log)
        m.presentFullScreen(style: .replaceAll) { D() }
        #expect(log.calls == expected)
        #expect(m.modalStack.count == 1)
        #expect(m.modalStack[0].style == .fullScreen)
        // only D (no coordinator root in unit tests)
        #expect(m.fullNavigationHistory.count == 1)
    }

    @Test func replaceOnEmptyStackIsSafe() {
        let m = makeManager()
        m.presentSheet(style: .replaceLast) { A() }
        m.presentSheet(style: .replaceAll) { B() }
        #expect(m.modalStack.count == 1)
    }
}

struct DismissToTests {
    @Test func dismissToAfterInterveningDismissSheet() {
        // Regression: positional indices went stale after dismissSheet.
        let m = makeManager(), log = Log()
        m.presentSheet(view: { A() }, onDismiss: log.on("A"))
        m.presentSheet(view: { B() }, onDismiss: log.on("B"))
        m.dismissSheet()                                   // B gone
        m.presentSheet(view: { C() }, onDismiss: log.on("C"))
        m.presentSheet(view: { D() }, onDismiss: log.on("D"))
        log.calls = []
        m.dismissTo(A.self, dismissalMode: .all)
        #expect(m.modalStack.count == 1)
        #expect(log.calls == ["D", "C"])
    }

    @Test(arguments: [
        (NavigationManager.DismissalMode.all, ["C.p", "C", "B.p", "B"]),
        (.topmost, ["C.p"]),
        (.landing, ["B"]),
    ])
    func dismissToHonorsMode(mode: NavigationManager.DismissalMode, expected: [String]) {
        let m = makeManager(), log = Log()
        m.presentSheet(view: { A() }, onDismiss: log.on("A"))
        m.presentSheet(view: { B() }, onDismiss: log.on("B"))
        m.push(view: { P() }, onDismiss: log.on("B.p"))
        m.presentSheet(view: { C() }, onDismiss: log.on("C"))
        m.push(view: { P() }, onDismiss: log.on("C.p"))
        m.dismissTo(A.self, dismissalMode: mode)
        #expect(log.calls == expected)
        #expect(m.modalStack.count == 1)
        #expect(m.modalPushPaths.count == 1)
    }

    @Test func dismissToRootViewType() {
        let m = makeManager()
        m.fullNavigationHistory = [NavigationItem(id: UUID(), viewTypeName: String(describing: A.self), type: .push, location: .root)]
        m.presentSheet { B() }
        m.presentSheet { C() }
        m.dismissTo(A.self)
        #expect(m.modalStack.isEmpty)
    }
}

struct NativePopTests {
    @Test func nativeModalPopTrimsHistory() {
        let m = makeManager(), log = Log()
        m.presentSheet { A() }
        m.push(view: { P() }, onDismiss: log.on("A.p"))
        let aID = m.modalStack[0].id
        m.modifyModalPushPath(for: aID) { $0.removeAll() }   // what the NavigationStack binding does on back-swipe
        #expect(log.calls == ["A.p"])
        #expect(m.fullNavigationHistory.last?.id == aID)
    }

    @Test func nativeRootPopTrimsHistory() {
        let m = makeManager(), log = Log()
        m.push(view: { P() }, onDismiss: log.on("p"))
        m.rootPushPath.removeAll()
        #expect(log.calls == ["p"])
        #expect(m.fullNavigationHistory.isEmpty)
    }
}

struct ChildModalTests {
    @Test func stackedEachModalIsItsOwnRung() {
        let m = makeManager()
        stackABC(m, Log(), withPushes: false, presentation: .stacked)
        let ids = m.modalStack.map(\.id)
        #expect(m.childModal(of: nil)?.id == ids[0])
        #expect(m.childModal(of: ids[0])?.id == ids[1])
        #expect(m.childModal(of: ids[1])?.id == ids[2])
        #expect(m.childModal(of: ids[2]) == nil)
    }

    @Test func swapCollapsesToOneRung() {
        let m = makeManager()
        stackABC(m, Log(), withPushes: false, presentation: .swap)
        let ids = m.modalStack.map(\.id)
        #expect(m.childModal(of: nil)?.id == ids[2])
        #expect(m.childModal(of: ids[2]) == nil)
        m.dismissSheet()
        #expect(m.childModal(of: nil)?.id == ids[1])
    }

    @Test func defaultComesFromManager() {
        let m = makeManager()
        #expect(m.defaultModalPresentationMode == .swap)
        m.defaultModalPresentationMode = .stacked
        m.presentSheet { A() }
        #expect(m.modalStack[0].presentation == .stacked)
    }

    @Test func mixedRungs() {
        // A, B(swap), C(stacked): root shows B, B shows C.
        let m = makeManager()
        m.presentSheet(presentation: .stacked) { A() }
        m.presentSheet(presentation: .swap) { B() }
        m.presentFullScreen(presentation: .stacked) { C() }
        let ids = m.modalStack.map(\.id)
        #expect(m.childModal(of: nil)?.id == ids[1])
        #expect(m.childModal(of: ids[1])?.id == ids[2])
        #expect(m.childModal(of: ids[0]) == nil)   // A is hidden
        m.dismissModal(id: ids[2])
        m.dismissModal(id: ids[1])
        #expect(m.childModal(of: nil)?.id == ids[0])
    }

    @Test func missingParentHasNoChild() {
        let m = makeManager()
        m.presentSheet(presentation: .stacked) { A() }
        #expect(m.childModal(of: UUID()) == nil)
    }
}
