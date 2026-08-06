import XCTest

// MARK: - Streamed thinking block (v0.2.0)

final class ThinkingStreamingTests: ChatUITestBase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--thinking-reply", "--no-text-animation"]
        app.launch()
    }

    /// The thinking toggle appears as soon as the reply message is appended
    /// (thinking is declared at creation — the frozen-rootView fix), streams
    /// content while collapsed, and the reply streams below it. The message
    /// settles to its full height once both blocks finish.
    func testThinkingToggleAppearsStreamsAndSettles() throws {
        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        tv.tap()
        tv.typeText("hello")
        app.buttons["send-button"].tap()

        // The toggle exists → the thinking block was declared at creation.
        let toggle = app.buttons["thinking-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Thinking toggle never appeared")

        // Expand it — the streamed thinking content becomes readable.
        toggle.tap()
        let thinking = app.textViews
            .matching(NSPredicate(format: "label CONTAINS %@", "Let me reason"))
            .firstMatch
        XCTAssertTrue(thinking.waitForExistence(timeout: 30), "Thinking content never streamed")

        // The reply still streams below, and everything settles.
        let assistant = assistantMessage()
        XCTAssertTrue(assistant.waitForExistence(timeout: 10), "Assistant bubble never appeared")
        XCTAssertTrue(waitForStableLayout(timeout: 60), "Stream did not settle")

        // The toggle persists through finish. No live "Done thinking" caption
        // is asserted: the cached hosting controller's rootView is frozen (the
        // no-flicker invariant — the live StreamedMarkdownView is never swapped
        // for static MarkdownView mid-session), so the per-block finish caption
        // only ever appears on re-created controllers (storage reload, or
        // eviction + scroll-back), not on the message that just streamed.
        XCTAssertTrue(toggle.exists, "Thinking toggle disappeared after settle")
    }

    /// Toggling the thinking block must flip its STATUS: collapsed by default
    /// (content hidden), expand → content visible, collapse → hidden again.
    /// Toggled 3× to prove the status toggles consistently.
    ///
    /// The observable is the message's HEIGHT, not `isHittable`: XCUITest's
    /// snapshot cannot see the collapsed state (SwiftUI `opacity(0)` +
    /// `maxHeight(0)` + `clipped()` + `allowsHitTesting(false)` keep the inner
    /// textView reported as hittable — verified, the collapse itself works and
    /// shrinks the message ~105 pt). Uses `--seed-thinking` (a normal reply, a
    /// user prompt, then a reply with thinking — both blocks finished, the
    /// post-stream state; the thinking message is the last visible one).
    func testThinkingToggleStatus() throws {
        app.terminate()
        app.launchArguments = ["--seed-thinking", "--no-text-animation"]
        app.launch()

        // Wait for the seeded conversation to appear, then give the initial
        // settle loop a beat to finish (it re-measures for ~24 ticks).
        let seedDeadline = Date().addingTimeInterval(10)
        while Date() < seedDeadline, app.buttons["thinking-toggle"].exists == false {
            Thread.sleep(forTimeInterval: 0.2)
        }
        Thread.sleep(forTimeInterval: 1.5)

        let toggle = app.buttons["thinking-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Thinking toggle never appeared")

        func messageHeight() -> CGFloat {
            visibleMessages().last?.frame.height ?? -1
        }
        /// The gap between the last message's bottom and the input bar top. A
        /// stuck-tall CELL (the growth-only observer never reports a shrink)
        /// leaves a blank below the collapsed bubble, so this gap is the
        /// observable for "the scroll-view height shrank with the collapse".
        func gapToInputBar() -> CGFloat {
            guard let last = visibleMessages().last, let bar = inputBarTop() else {
                return .greatestFiniteMagnitude
            }
            return bar - last.frame.maxY
        }

        // Collapsed by default — the shortest the message gets.
        let collapsedHeight = messageHeight()

        for i in 1...3 {
            toggle.tap()  // expand — the thinking content reveals, message grows
            XCTAssertTrue(waitForStableLayout(timeout: 20), "Layout did not settle after expand \(i)")
            let expandedHeight = messageHeight()
            print(">>> thinking toggle \(i): expand \(collapsedHeight) → \(expandedHeight)")
            XCTAssertGreaterThan(expandedHeight, collapsedHeight + 40,
                "Toggle \(i): thinking did not expand (message should grow by the thinking height)")

            toggle.tap()  // collapse — the thinking content hides, message shrinks
            XCTAssertTrue(waitForStableLayout(timeout: 20), "Layout did not settle after collapse \(i)")
            let reCollapsedHeight = messageHeight()
            print(">>> thinking toggle \(i): collapse \(expandedHeight) → \(reCollapsedHeight)")
            XCTAssertLessThan(reCollapsedHeight, expandedHeight - 40,
                "Toggle \(i): thinking did not collapse (message should shrink by the thinking height)")

            // The CELL (scroll-view height) must shrink with the collapse: a
            // stuck-tall cell leaves a blank below the collapsed bubble. This
            // asserts the fix for the "collapse doesn't shrink" bug.
            let collapseGap = gapToInputBar()
            print(">>> thinking toggle \(i): gap to input bar \(collapseGap)pt")
            XCTAssertLessThan(collapseGap, 60,
                "Toggle \(i): collapse left a \(collapseGap)pt blank — the cell did not shrink")
        }
    }
}
