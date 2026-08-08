import XCTest

// MARK: - Consumer pinned top band (status bar)

/// Proves the demo's consumer-owned top band is CONTROLLED by and INTERACTIVE
/// with the app — not a static decal:
///   1. It reflects live chat state: "Ready" when idle → "Assistant is typing…"
///      while a reply streams → "Ready" when it finishes.
///   2. It drives the app: the Clear button calls through the consumer's
///      `StubChatService` and empties the conversation.
final class BannerInteractionTests: ChatUITestBase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // --no-auto-send: keep the conversation static so the banner's state
        // transitions are deterministic (no demo stream racing the assertions).
        // --no-text-animation: the suite exercises the stable render.
        app.launchArguments = ["--no-auto-send", "--no-text-animation"]
        app.launch()
    }

    func testStatusBarReflectsAndDrivesChat() throws {
        let banner = app.descendants(matching: .any).matching(identifier: "status-bar").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "Status bar never appeared")

        // Idle → Ready.
        let ready = app.staticTexts["Ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 5), "Banner should show Ready when idle")

        // Send a message → the reply streams → the banner flips to typing state.
        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        tv.tap()
        tv.typeText("hello banner")
        app.buttons["send-button"].tap()

        let typing = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Assistant is typing"))
            .firstMatch
        XCTAssertTrue(typing.waitForExistence(timeout: 30), "Banner never showed the streaming state")

        // After the stream finishes, the banner returns to Ready.
        XCTAssertTrue(waitForStableLayout(timeout: 60), "Stream did not settle")
        XCTAssertTrue(ready.waitForExistence(timeout: 30), "Banner did not return to Ready after finish")

        // The Clear button drives the app through the consumer's service.
        app.buttons["banner-clear-button"].tap()
        XCTAssertTrue(waitForEmptyConversation(timeout: 10), "Clear did not empty the conversation")
    }

    /// The pinned band must RESERVE space, not cover it. Asserted on the
    /// collection view's own frame (accurate UIKit geometry — the message
    /// container): its top edge sits at or below the banner's bottom edge, so
    /// the topmost message inside it cannot be occluded. Uses a static seeded
    /// list (`--seed-messages 3`).
    ///
    /// NOTE: we deliberately do NOT assert on a message bubble's accessibility
    /// frame here. A bubble reports its frame in the hosted content's space and
    /// is offset by the banner (observed first.minY=49 vs banner.maxY=102 —
    /// open issue #10, same cached-hosting root as #9), so a bubble-frame
    /// assertion fails on the reporting artifact, not the layout.
    func testBannerDoesNotOccludeFirstMessage() throws {
        app.terminate()
        app.launchArguments = ["--seed-messages", "3", "--no-auto-send", "--no-text-animation"]
        app.launch()

        let banner = app.descendants(matching: .any).matching(identifier: "status-bar").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "Status bar never appeared")
        let bannerMaxY = banner.frame.maxY

        let collectionView = app.collectionViews.firstMatch
        XCTAssertTrue(collectionView.waitForExistence(timeout: 10), "Collection view never appeared")
        let collectionMinY = collectionView.frame.minY
        print(">>> banner.maxY=\(bannerMaxY) collection.minY=\(collectionMinY) gap=\(collectionMinY - bannerMaxY)")
        XCTAssertGreaterThanOrEqual(collectionMinY, bannerMaxY - 2,
            "Message list occluded by banner: banner.maxY=\(bannerMaxY) collection.minY=\(collectionMinY)")
    }

    /// Polls until no message bubbles remain (the consumer's Clear action emptied
    /// the list). Can't reuse waitForMessageCount(0) — its `>= count` comparison
    /// returns true immediately for 0.
    private func waitForEmptyConversation(timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let user = app.descendants(matching: .any).matching(identifier: "user-msg").count
            let assistant = app.descendants(matching: .any).matching(identifier: "assistant-msg").count
            if user == 0 && assistant == 0 { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }
}
