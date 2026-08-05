import XCTest

// UI automation for the sample chat app (cached-hosting-controller streaming
// markdown in a UICollectionView). Launch args:
//   --seed-messages N  → pre-fill N user+assistant pairs (KeyboardPushTests)
//   --long-reply       → deterministic long markdown reply (StreamingFlickerTests)
//
// The push-up suite asserts the three bug repros are FIXED:
//   • no scroll down into a keyboard-height blank
//   • short content is bottom-anchored (no blank below the last message)
//   • push-up is not doubled for short content
// The flicker suite asserts the streaming bubble grows in place without being
// recreated (the thing every previous fix broke).

/// Shared helpers for the sample chat UI tests.
class ChatUITestBase: XCTestCase {
    let app = XCUIApplication()

    func sendMessage(_ text: String) {
        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        tv.tap()
        tv.typeText(text)
        app.buttons["send-button"].tap()
    }

    func dismissKeyboard() {
        let topOfScreen = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        topOfScreen.tap()
    }

    /// Message bubbles sorted by vertical position (top to bottom). Matches by
    /// accessibility identifier, so it works on the SwiftUI content hosted in
    /// the collection cells.
    ///
    /// Querying is race-resistant: `.count` is snapshotted first (safe — the
    /// per-element index race only bites binding), then elements are bound by
    /// index. A live stream insert between the snapshot and a bind can still
    /// shift the list, so callers that query while streaming should re-query
    /// (see waitForStableLayout), but the double-`allElementsBoundByIndex`
    /// window that produced "No matches found for Element at index N" is gone.
    func visibleMessages() -> [XCUIElement] {
        let userQuery = app.descendants(matching: .any).matching(identifier: "user-msg")
        let assistantQuery = app.descendants(matching: .any).matching(identifier: "assistant-msg")
        var result: [XCUIElement] = []
        let userCount = userQuery.count
        let assistantCount = assistantQuery.count
        for i in 0..<userCount { result.append(userQuery.element(boundBy: i)) }
        for i in 0..<assistantCount { result.append(assistantQuery.element(boundBy: i)) }
        return result.filter { $0.exists }.sorted { $0.frame.minY < $1.frame.minY }
    }

    /// The (single) assistant bubble — the streaming reply.
    func assistantMessage() -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "assistant-msg").firstMatch
    }

    /// The input bar's top edge. The text view has an 8pt top inset within the
    /// bar, so `textView.frame.minY - 8` is the bar's top.
    func inputBarTop() -> CGFloat? {
        let tv = app.textViews["input-textview"]
        guard tv.exists else { return nil }
        return tv.frame.minY - 8
    }

    /// Polls until at least `count` message bubbles exist in the accessibility
    /// hierarchy. A send appends the user cell and starts the assistant reply
    /// asynchronously; querying for the last message during that insert can
    /// race cell reuse and throw "No matches found for Element at index N"
    /// (flaky under load). Waiting for the count first lets the insert land, so
    /// the layout-stability checks below never snapshot a half-built list.
    /// Uses `.count` (not `.allElementsBoundByIndex`) so the poll itself cannot
    /// trip the per-element index race.
    @discardableResult
    func waitForMessageCount(_ count: Int, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let userCount = app.descendants(matching: .any).matching(identifier: "user-msg").count
            let assistantCount = app.descendants(matching: .any).matching(identifier: "assistant-msg").count
            if userCount + assistantCount >= count { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// Polls until the last message's bottom edge and the keyboard top are both
    /// stable across consecutive samples (animation/layout fully settled).
    @discardableResult
    func waitForStableLayout(timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastSample: (keyTop: CGFloat, msgMaxY: CGFloat)?
        while Date() < deadline {
            let keyTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : -1
            guard let msgMaxY = visibleMessages().last?.frame.maxY else {
                Thread.sleep(forTimeInterval: 0.2)
                continue
            }
            if let lastSample,
               abs(keyTop - lastSample.keyTop) < 0.5,
               abs(msgMaxY - lastSample.msgMaxY) < 0.5 {
                return true
            }
            lastSample = (keyTop, msgMaxY)
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// Scroll up a tiny amount (within the 100px nearBottom threshold).
    /// Slow-velocity drag with a hold — XCUI's default drag is a flick whose
    /// momentum overshoots the 100pt guard (observed: 25pt finger → 264pt
    /// scroll). `.slow` + hold kills the momentum so the net scroll stays
    /// under 100pt while still visibly moving.
    func scrollUpSmallAmount() {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let to   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.4)
        sleep(1)
    }

    /// Scroll up past the 100px nearBottom threshold to test the guard blocks push.
    func scrollUpLargeAmount() {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let to   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        from.press(forDuration: 0.3, thenDragTo: to)
        sleep(1)
    }
}
