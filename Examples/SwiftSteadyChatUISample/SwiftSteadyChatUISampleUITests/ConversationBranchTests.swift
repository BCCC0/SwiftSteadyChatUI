import XCTest

// MARK: - Conversation branching + re-entry restuff (--branch-demo)

/// Proves the store-backed history REALLY branches and restuffs. The two seeded
/// conversations have DISTINCT content ("Alice message …" vs "Bob message …"), so
/// the tests assert by text — message counts can't prove it because off-screen
/// cells aren't materialized in the accessibility tree.
final class ConversationBranchTests: ChatUITestBase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // --branch-demo: two conversations sharing one SwiftData store.
        // --in-memory: hermetic per launch. --no-auto-send / --no-text-animation: stable.
        app.launchArguments = ["--branch-demo", "--no-auto-send", "--no-text-animation", "--in-memory"]
        app.launch()
    }

    /// Branching: Alice and Bob show DIFFERENT histories, keyed by conversationId.
    func testTwoConversationsShowDifferentHistories() throws {
        let alice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Alice message 1")).firstMatch
        XCTAssertTrue(alice.waitForExistence(timeout: 30), "Alice's history not shown on entry")

        // Branch to Bob — his DISTINCT history replaces Alice's.
        app.segmentedControls.firstMatch.buttons["Bob"].tap()
        let bob = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Bob message 1")).firstMatch
        XCTAssertTrue(bob.waitForExistence(timeout: 30), "Bob's history not shown after branching")
        XCTAssertFalse(alice.exists, "Alice's history should not be shown after branching to Bob")
    }

    /// Restuff: a message sent in Bob SURVIVES switching to Alice and back — the
    /// re-entered Bob hydrates his history from SwiftData, sent message included.
    func testReentryRestoresSentMessagesFromStore() throws {
        // Open Bob.
        app.segmentedControls.firstMatch.buttons["Bob"].tap()
        let bob = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Bob message 1")).firstMatch
        XCTAssertTrue(bob.waitForExistence(timeout: 30), "Bob's history not shown")

        // Send a message in Bob → the user message persists to the store
        // SYNCHRONOUSLY with its appearance (sendMessage appends to messages AND
        // store.append before notifying). The reply may still be streaming — that's
        // fine; the restuff proof is the sent message, which only exists after
        // re-entry via the store. (We deliberately avoid waitForStableLayout here:
        // its visibleMessages()/allElementsBoundByIndex races the streaming insert.)
        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        tv.tap()
        tv.typeText("persist me")
        app.buttons["send-button"].tap()
        XCTAssertTrue(app.staticTexts["persist me"].waitForExistence(timeout: 60), "Sent message did not appear")

        // Branch to Alice (a different conversation), then BACK to Bob.
        app.segmentedControls.firstMatch.buttons["Alice"].tap()
        let alice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Alice message 1")).firstMatch
        XCTAssertTrue(alice.waitForExistence(timeout: 30), "Alice's history not shown after branching")
        app.segmentedControls.firstMatch.buttons["Bob"].tap()

        // THE RESTUFF: Bob's re-entered service is FRESH — it hydrated only from
        // SwiftData. So the sent "persist me" message is STILL here only because the
        // store refilled Bob's history with it. (The seeded "Bob message 1" is
        // scrolled off-screen after the list follows the bottom, so it's not in the
        // accessibility tree — the sent message is the deterministic restuff signal.)
        XCTAssertTrue(app.staticTexts["persist me"].waitForExistence(timeout: 30),
            "Bob lost the sent message — restuff did not restore it from SwiftData")
    }

    /// The FULL re-entry: terminate the app and relaunch it. With the ON-DISK store
    /// (no `--in-memory`), a message sent before termination must be restored from
    /// SwiftData after the relaunch — the real re-entry restuff. (The in-memory
    /// config used by the other tests intentionally does NOT survive a relaunch.)
    func testRelaunchRestoresSentMessageFromDisk() throws {
        app.terminate()
        // CLEAN start: --reset-branch clears both conversations' on-disk records,
        // then the demo re-seeds fresh. This makes the test hermetic (no data from
        // a prior run) and keeps the simulator's on-disk store from accumulating.
        app.launchArguments = ["--branch-demo", "--reset-branch", "--no-auto-send", "--no-text-animation"]
        app.launch()

        // Open Bob, send a UNIQUE marker (a timestamped string — never a false
        // positive from a prior run's on-disk data).
        app.segmentedControls.firstMatch.buttons["Bob"].tap()
        let marker = "persist-\(Int(Date().timeIntervalSince1970))"
        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        tv.tap()
        tv.typeText(marker)
        app.buttons["send-button"].tap()
        XCTAssertTrue(app.staticTexts[marker].waitForExistence(timeout: 60),
            "Sent marker did not appear before relaunch")

        // Full relaunch — WITHOUT --reset-branch, so the on-disk store is preserved.
        app.terminate()
        app.launchArguments = ["--branch-demo", "--no-auto-send", "--no-text-animation"]
        app.launch()

        // Re-enter Bob → the marker is restored from the on-disk store. If the
        // store didn't refill across a real relaunch, the marker would be gone.
        app.segmentedControls.firstMatch.buttons["Bob"].tap()
        XCTAssertTrue(app.staticTexts[marker].waitForExistence(timeout: 30),
            "Sent marker was lost across relaunch — the on-disk store did not refill it (restuff failed)")

        // CLEANUP: relaunch with --reset-branch so the on-disk store doesn't
        // accumulate the marker/seed data across runs.
        app.terminate()
        app.launchArguments = ["--branch-demo", "--reset-branch", "--no-auto-send", "--no-text-animation"]
        app.launch()
    }

    /// CONTRAST: with the IN-MEMORY store (`--in-memory`), a sent message is LOST on
    /// a full relaunch — the in-memory config does not persist to disk by design.
    /// This pins the root cause of "persist me is lost on re-enter": it is the store
    /// configuration, NOT the restuff (which the on-disk test above proves).
    func testRelaunchLosesMessageWithInMemoryStore() throws {
        app.terminate()
        app.launchArguments = ["--branch-demo", "--no-auto-send", "--no-text-animation", "--in-memory"]
        app.launch()

        app.segmentedControls.firstMatch.buttons["Bob"].tap()
        let marker = "volatile-\(Int(Date().timeIntervalSince1970))"
        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        tv.tap()
        tv.typeText(marker)
        app.buttons["send-button"].tap()
        XCTAssertTrue(app.staticTexts[marker].waitForExistence(timeout: 60), "Marker did not appear")

        app.terminate()
        app.launch()

        // Re-enter Bob — the in-memory store was wiped by the relaunch, so the
        // marker must be GONE (the expected, by-design loss for --in-memory).
        app.segmentedControls.firstMatch.buttons["Bob"].tap()
        XCTAssertTrue(app.staticTexts[marker].waitForNonExistence(timeout: 30),
            "In-memory store should NOT persist across a relaunch — the marker should be gone")
    }

    /// The drop list wires delete: long-press a message → Delete → the message
    /// disappears from the UI AND the SwiftData store (re-entry doesn't restore it).
    func testDropListDeleteRemovesFromUIAndStore() throws {
        // Bob seeded with "Bob message 1..5" / "Bob reply 1..5". Open Bob and
        // target the LAST seeded pair — "Bob message 5"/"Bob reply 5" are
        // bottom-adjacent and ON-SCREEN after the initial scroll-to-bottom
        // ("Bob message 1" is scrolled off-screen and can't be long-pressed).
        app.segmentedControls.firstMatch.buttons["Bob"].tap()
        // Message bubbles expose their text at different element types (a user
        // prompt is a staticText; a markdown reply is not), so match on ANY
        // element whose label contains the seeded text.
        let bobMsg5 = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Bob message 5")).firstMatch
        XCTAssertTrue(bobMsg5.waitForExistence(timeout: 30), "Bob's history not shown")

        // Long-press a bottom-adjacent seeded message → the consumer's drop list appears.
        bobMsg5.press(forDuration: 1.2)
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10), "Delete action did not appear in the drop list")
        deleteButton.tap()

        // The deleted message is gone from the UI.
        XCTAssertTrue(bobMsg5.waitForNonExistence(timeout: 10), "Deleted message still visible")

        // And it's gone from the STORE: switch away + back → not restored. The
        // POSITIVE CONTROL — surviving neighbor "Bob reply 5" IS present after
        // re-entry — makes the deleted message's absence meaningful (the whole
        // Bob history fits the viewport, so a surviving record would be on screen,
        // not an off-screen false negative).
        let bobReply5 = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Bob reply 5")).firstMatch
        app.segmentedControls.firstMatch.buttons["Alice"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Alice message 1")).firstMatch.waitForExistence(timeout: 30))
        app.segmentedControls.firstMatch.buttons["Bob"].tap()
        XCTAssertTrue(bobReply5.waitForExistence(timeout: 30),
            "Surviving neighbor lost — the restuffed history is missing a message that was NOT deleted (harness broken)")
        XCTAssertTrue(bobMsg5.waitForNonExistence(timeout: 30),
            "Deleted message was restored from the store — the record was not deleted")
    }
}
