//
//  ModalStackUITests.swift
//  NavigationFrame3UITests
//
//  Drives ModalStackHarness (the "Stack" tab, coordinator in .stacked mode).
//

import XCTest

final class ModalStackUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Stack"].tap()
    }

    // MARK: - Helpers

    private func tap(_ id: String) {
        let element = app.buttons[id].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(id)")
        element.tap()
    }

    private func text(_ id: String) -> String {
        let element = app.staticTexts[id].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(id)")
        return element.label
    }

    private func field(_ id: String) -> String {
        app.textFields[id].firstMatch.value as? String ?? ""
    }

    private func type(_ value: String, into id: String) {
        let element = app.textFields[id].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()
        element.typeText(value)
    }

    private func waitForLevel(_ name: String) {
        XCTAssertTrue(app.staticTexts["\(name).title"].waitForExistence(timeout: 5), "level \(name) not shown")
    }

    private func waitForStack(_ count: Int) {
        let predicate = NSPredicate(format: "label == %@", "stack \(count)")
        let element = app.staticTexts.matching(identifier: "stack.count").firstMatch
        expectation(for: predicate, evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    /// Fills a level with state we can check later.
    private func dirty(_ name: String, text: String, taps: Int) -> String {
        waitForLevel(name)
        for _ in 0..<taps { tap("\(name).inc") }
        type(text, into: "\(name).field")
        return self.text("\(name).vm")
    }

    private func assertIntact(_ name: String, vm: String, text expected: String, counter: Int,
                              file: StaticString = #filePath, line: UInt = #line) {
        waitForLevel(name)
        XCTAssertEqual(text("\(name).vm"), vm, "\(name) view model was recreated", file: file, line: line)
        XCTAssertEqual(text("\(name).counter"), "\(counter)", "\(name) @State counter reset", file: file, line: line)
        XCTAssertEqual(field("\(name).field"), expected, "\(name) TextField reset", file: file, line: line)
        XCTAssertEqual(text("\(name).appear"), "appear 1", "\(name) .onAppear re-fired", file: file, line: line)
        XCTAssertEqual(text("\(name).task"), "task 1", "\(name) .task re-fired", file: file, line: line)
    }

    // MARK: - Tests

    func testABCThenBackPreservesEveryLevel() {
        tap("root.presentA")
        let aVM = dirty("A", text: "alpha", taps: 2)
        tap("A.sheet")
        let bVM = dirty("B", text: "bravo", taps: 1)
        tap("B.sheet")
        _ = dirty("C", text: "charlie", taps: 3)

        tap("C.dismiss")
        waitForStack(2)
        assertIntact("B", vm: bVM, text: "bravo", counter: 1)

        tap("B.dismiss")
        waitForStack(1)
        assertIntact("A", vm: aVM, text: "alpha", counter: 2)
    }

    func testPushedViewInsideSheetSurvivesNestedSheet() {
        tap("root.presentA")
        waitForLevel("A")
        tap("A.push")
        let pVM = dirty("A-P", text: "pushed", taps: 2)
        tap("A-P.sheet")
        waitForLevel("B")
        tap("B.dismiss")
        waitForStack(1)
        assertIntact("A-P", vm: pVM, text: "pushed", counter: 2)
    }

    func testSwipeDismissTopSheet() {
        tap("root.presentA")
        waitForLevel("A")
        tap("A.sheet")
        let bVM = dirty("B", text: "bravo", taps: 1)
        tap("B.sheet")
        waitForLevel("C")

        // Drag the sheet down by its top edge (a swipe on the content just scrolls the ScrollView)
        let sheetTop = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        sheetTop.press(forDuration: 0.1, thenDragTo: bottom, withVelocity: .fast, thenHoldForDuration: 0)
        waitForStack(2)
        XCTAssertFalse(app.staticTexts["C.title"].exists)
        XCTAssertTrue(text("dismissed.log").hasSuffix("C"))
        assertIntact("B", vm: bVM, text: "bravo", counter: 1)
    }

    func testMixedSheetAndFullScreen() {
        tap("root.presentA")
        let aVM = dirty("A", text: "alpha", taps: 1)
        tap("A.cover")
        waitForLevel("B")
        tap("B.inc")
        let bVM = text("B.vm")
        tap("B.sheet")
        waitForLevel("C")
        XCTAssertTrue(app.staticTexts["C.title"].isHittable, "sheet over full screen cover not visible")

        tap("C.dismiss")
        waitForStack(2)
        waitForLevel("B")
        XCTAssertEqual(text("B.vm"), bVM)
        XCTAssertEqual(text("B.counter"), "1")

        tap("B.dismiss")
        waitForStack(1)
        // A was fully covered by a full screen cover, so UIKit re-fires onAppear; state must survive.
        waitForLevel("A")
        XCTAssertEqual(text("A.vm"), aVM)
        XCTAssertEqual(text("A.counter"), "1")
        XCTAssertEqual(field("A.field"), "alpha")
    }

    func testDismissToA() {
        tap("root.presentA")
        let aVM = dirty("A", text: "alpha", taps: 1)
        tap("A.sheet")
        waitForLevel("B")
        tap("B.sheet")
        waitForLevel("C")

        tap("C.dismissToA")
        waitForStack(1)
        XCTAssertEqual(text("dismissed.log"), "dismissed C,B")   // coordinator uses .all
        assertIntact("A", vm: aVM, text: "alpha", counter: 1)
    }

    func testReplaceLastKeepsLowerLevels() {
        tap("root.presentA")
        let aVM = dirty("A", text: "alpha", taps: 1)
        tap("A.sheet")
        let bVM = dirty("B", text: "bravo", taps: 1)
        tap("B.sheet")
        waitForLevel("C")
        let oldC = text("C.vm")

        tap("C.replaceLast")
        waitForStack(3)
        waitForLevel("C")
        XCTAssertNotEqual(text("C.vm"), oldC, "replaceLast should show a new modal")

        tap("C.dismiss")
        waitForStack(2)
        assertIntact("B", vm: bVM, text: "bravo", counter: 1)
        tap("B.dismiss")
        waitForStack(1)
        assertIntact("A", vm: aVM, text: "alpha", counter: 1)
    }

    func testReplaceAll() {
        tap("root.presentA")
        waitForLevel("A")
        tap("A.sheet")
        waitForLevel("B")
        tap("B.replaceAll")
        waitForStack(1)
        XCTAssertEqual(text("dismissed.log"), "dismissed B,A")
        waitForLevel("A")
    }

    func testPresentTwoInOneTap() {
        tap("root.presentAB")
        waitForStack(2)
        waitForLevel("B")
        XCTAssertTrue(app.staticTexts["B.title"].isHittable, "second modal dropped when presented in the same tap")
    }

    func testSwapModeRebuildsCoveredSheet() {
        tap("root.presentA")
        _ = dirty("A", text: "alpha", taps: 2)
        tap("A.swap")
        waitForLevel("B")
        tap("B.dismiss")
        waitForStack(1)
        waitForLevel("A")
        XCTAssertEqual(text("A.counter"), "0", ".swap should rebuild the covered sheet fresh")
        XCTAssertEqual(text("A.appear"), "appear 2")
    }
}

extension ModalStackUITests {
    /// Known limitation: a sheet embeds its own NavigationCoordinator whose inner sheet is open,
    /// and the outer manager stacks another sheet on that same sheet. iOS only allows one
    /// presentation per screen, so B waits in modalStack and appears once the inner sheet closes.
    func testInnerCoordinatorSheetThenOuterStack() {
        tap("root.presentA")
        waitForLevel("A")
        tap("A.inner")
        tap("inner.present")
        XCTAssertTrue(app.staticTexts["inner.title"].waitForExistence(timeout: 5))
        tap("inner.presentOuter")
        let bShownOverInner = app.staticTexts["B.title"].waitForExistence(timeout: 3)
        XCTAssertFalse(bShownOverInner)
        XCTAssertEqual(text("inner.outerCount"), "outer stack 2")

        // Close the inner sheet; does the pending outer B appear afterwards?
        let sheetTop = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09))
        sheetTop.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)),
                       withVelocity: .fast, thenHoldForDuration: 0)
        let bShownAfter = app.staticTexts["B.title"].waitForExistence(timeout: 5)
        XCTAssertTrue(bShownAfter, "queued outer sheet should appear once the inner sheet closes")
    }
}

/// Tab 1 uses the default `.swap` mode: today's one-sheet-at-a-time behavior must hold.
final class SwapModeRegressionUITests: XCTestCase {
    func testSwapIsTheDefaultAndDismissToReachesRoot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        app.buttons["Present ViewC"].firstMatch.tap()
        let viewC = app.staticTexts["🌊 ViewC (Presented from B)"]
        XCTAssertTrue(viewC.waitForExistence(timeout: 5))

        app.buttons["Present ViewD"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["🧱 ViewD (Side Menu)"].waitForExistence(timeout: 5))
        // .swap: ViewC is torn down while ViewD is up
        XCTAssertFalse(viewC.exists)

        app.buttons["Dismiss sheet"].firstMatch.tap()
        XCTAssertTrue(viewC.waitForExistence(timeout: 5))

        // Root is registered as "ViewB" again, so dismissTo(ViewB.self) lands on the tab root
        app.buttons["Dismiss to ViewB"].firstMatch.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: viewC)
        waitForExpectations(timeout: 5)
    }
}

/// The ViewC → ViewD → ViewE → ViewF demo path used to try replaceLast / replaceAll by hand.
final class ReplaceDemoPathUITests: XCTestCase {
    /// Lower sheets stay in the accessibility tree, so pick the copy that's actually on top.
    private func tapVisible(_ label: String, in app: XCUIApplication) {
        let match = app.buttons.matching(identifier: label).allElementsBoundByIndex.last { $0.isHittable }
        XCTAssertNotNil(match, "no visible \(label)")
        match?.tap()
    }

    private func openC_D_E(_ app: XCUIApplication) -> XCUIElement {
        app.launch()
        app.buttons["Present ViewC"].firstMatch.tap()
        app.buttons["Sheet · stacked (C stays behind)"].firstMatch.tap()
        app.buttons["Present ViewE · stacked"].firstMatch.tap()
        let readout = app.staticTexts["Open sheets: ViewC → ViewD → ViewE"].firstMatch
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        return readout
    }

    func testReplaceLastFromE() {
        let app = XCUIApplication()
        _ = openC_D_E(app)
        app.buttons["Replace last (E closed for good)"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Open sheets: ViewC → ViewD → ViewF"].firstMatch.waitForExistence(timeout: 5))
        tapVisible("Dismiss sheet", in: app)
        XCTAssertTrue(app.staticTexts["Open sheets: ViewC → ViewD"].firstMatch.waitForExistence(timeout: 5))
    }

    func testReplaceAllFromE() {
        let app = XCUIApplication()
        _ = openC_D_E(app)
        app.buttons["Replace all (every sheet closed)"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Open sheets: ViewF"].firstMatch.waitForExistence(timeout: 5))
        tapVisible("Dismiss sheet", in: app)
        XCTAssertTrue(app.buttons["Present ViewC"].firstMatch.waitForExistence(timeout: 5))
    }
}
