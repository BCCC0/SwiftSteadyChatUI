import XCTest

// MARK: - Streamed thinking block (v0.2.0)

final class ThinkingStreamingTests: ChatUITestBase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--thinking-reply", "--no-text-animation", "--in-memory"]
        app.launch()
    }

    /// The thinking toggle appears as soon as the thinking message is appended
    /// (thinking is declared at creation — the frozen-rootView fix), streams
    /// content while collapsed, and the reply streams in a SEPARATE bubble
    /// below it. Both bubbles settle to their full height once the reply
    /// finishes.
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

        // The reply streams below in its OWN bubble — the LAST visible message.
        // `assistantMessage()` (firstMatch) would resolve to the finished
        // thinking bubble above it, so wait for the reply to be appended
        // (user + thinking + reply) and let the whole list settle.
        XCTAssertTrue(waitForMessageCount(3, timeout: 30), "Reply bubble never appeared")
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
    /// shrinks the bubble ~105 pt). Uses `--seed-thinking`, which seeds
    /// [reply, user, thinking, reply] (all finished — the post-stream state).
    /// The thinking bubble is the SECOND-TO-LAST visible message; the last is
    /// a finished reply, so `visibleMessages().last` no longer points at the
    /// toggle — the geometry is measured on the message above the last.
    func testThinkingToggleStatus() throws {
        app.terminate()
        app.launchArguments = ["--seed-thinking", "--no-text-animation", "--in-memory"]
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

        /// The thinking bubble — the second-to-last visible message (the last
        /// is the finished reply below it).
        func thinkingBubble() -> XCUIElement? {
            let msgs = visibleMessages()
            guard msgs.count >= 2 else { return nil }
            return msgs[msgs.count - 2]
        }
        func thinkingHeight() -> CGFloat {
            guard let thinking = thinkingBubble() else { return -1 }
            return thinking.frame.height
        }
        /// The tallest visible message — the finished reply below the thinking
        /// bubble (the longStreamingReply). Its HEIGHT is a reliable observable
        /// for "the reply cell is untouched by the thinking toggle".
        func maxVisibleHeight() -> CGFloat {
            visibleMessages().map { $0.frame.height }.max() ?? -1
        }

        // Collapsed by default — the shortest the bubble gets.
        let collapsedHeight = thinkingHeight()
        let replyHeight = maxVisibleHeight()

        // NOTE: position-based assertions (gaps between bubbles) are NOT
        // reliable here — after toggling a NON-last bubble, the SwiftUI
        // accessibility frame for that bubble is stale (reported far above its
        // real position), corrupting visibleMessages() ordering. The app's
        // actual cell layout is correct (verified via layoutAttributes — the
        // thinking cell collapses and the reply below moves up, no real
        // overlap). So this test asserts the RELIABLE signals: the thinking
        // bubble's HEIGHT returns to compact, and the reply's HEIGHT is stable.
        for i in 1...3 {
            toggle.tap()  // expand — the thinking content reveals, bubble grows
            XCTAssertTrue(waitForStableLayout(timeout: 20), "Layout did not settle after expand \(i)")
            let expandedHeight = thinkingHeight()
            print(">>> thinking toggle \(i): expand \(collapsedHeight) → \(expandedHeight)")
            XCTAssertGreaterThan(expandedHeight, collapsedHeight + 40,
                "Toggle \(i): thinking did not expand (bubble should grow by the thinking height)")

            toggle.tap()  // collapse — the thinking content hides, bubble shrinks
            XCTAssertTrue(waitForStableLayout(timeout: 20), "Layout did not settle after collapse \(i)")
            let reCollapsedHeight = thinkingHeight()
            print(">>> thinking toggle \(i): collapse \(expandedHeight) → \(reCollapsedHeight)")
            XCTAssertLessThan(reCollapsedHeight, expandedHeight - 40,
                "Toggle \(i): thinking did not collapse (bubble should shrink by the thinking height)")
            // Returns to the compact height — no stuck-tall residual.
            XCTAssertEqual(reCollapsedHeight, collapsedHeight, accuracy: 25,
                "Toggle \(i): collapsed height drifted from \(collapsedHeight) to \(reCollapsedHeight)")

            // The reply cell (the tallest message) is untouched by the toggle.
            let replyAfter = maxVisibleHeight()
            XCTAssertEqual(replyAfter, replyHeight, accuracy: 30,
                "Toggle \(i): reply height changed \(replyHeight) → \(replyAfter) — the reply cell was disturbed by the thinking toggle")
        }
    }
}
