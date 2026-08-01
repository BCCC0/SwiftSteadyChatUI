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
}
