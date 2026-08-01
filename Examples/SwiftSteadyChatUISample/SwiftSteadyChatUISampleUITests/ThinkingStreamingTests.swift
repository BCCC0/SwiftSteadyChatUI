import XCTest

// MARK: - Streamed thinking block (v0.2.0)

final class ThinkingStreamingTests: ChatUITestBase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--thinking-reply"]
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
    /// (content hidden → not hittable), expand → content visible (hittable),
    /// collapse → hidden again. Toggled 3× to prove the status toggles
    /// consistently. Uses `--seed-thinking` (a normal reply, a user prompt, then
    /// a reply with thinking — both blocks finished, the post-stream state).
    func testThinkingToggleStatus() throws {
        app.terminate()
        app.launchArguments = ["--seed-thinking"]
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

        // The thinking content is collapsed by default (maxHeight 0 / opacity 0),
        // so it is not hittable.
        let thinking = app.textViews.matching(NSPredicate(format: "label CONTAINS %@", "Let me reason")).firstMatch
        XCTAssertFalse(thinking.isHittable, "Thinking should be collapsed (hidden) by default")

        for i in 1...3 {
            toggle.tap()  // expand
            XCTAssertTrue(waitForStableLayout(timeout: 20), "Layout did not settle after expand \(i)")
            print(">>> thinking toggle \(i): expand → status \(thinking.isHittable ? "expanded" : "collapsed")")
            XCTAssertTrue(thinking.isHittable, "Toggle \(i): thinking did not expand (status should be expanded)")

            toggle.tap()  // collapse
            XCTAssertTrue(waitForStableLayout(timeout: 20), "Layout did not settle after collapse \(i)")
            print(">>> thinking toggle \(i): collapse → status \(thinking.isHittable ? "expanded" : "collapsed")")
            XCTAssertFalse(thinking.isHittable, "Toggle \(i): thinking did not collapse (status should be collapsed)")
        }
    }
}
