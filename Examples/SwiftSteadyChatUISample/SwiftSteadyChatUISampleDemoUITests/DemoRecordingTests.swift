import XCTest

// MARK: - Recording-only demo tests (video production)
//
// Three paced demos, each ending on a settled "hold" frame so the recorded
// video ends elegantly (the recording script trims the app-termination tail).
// Run them via the `SwiftSteadyChatUISampleDemo` scheme + the record script
// (see `scripts/record-demo.sh`), NOT as part of the normal suite.

final class DemoRecordingTests: DemoUITestBase {

    // MARK: Demo 1 — empty conversation → prompt → long streaming reply

    func testDemo1StreamingLongReply() throws {
        app.launchArguments = ["--long-reply", "--in-memory"]   // no seed → truly empty conversation
        app.launch()

        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        sleep(1)   // let the empty state settle on screen

        tv.tap()
        tv.typeText("hello")
        sleep(1)
        app.buttons["send-button"].tap()

        XCTAssertTrue(assistantMessage().waitForExistence(timeout: 10),
            "Assistant bubble never appeared")
        XCTAssertTrue(waitForStableLayout(timeout: 30),
            "Stream did not settle after the long reply")
        sleep(2)   // hold the completed markdown on screen
    }

    // MARK: Demo 2 — keyboard push-up → tap background to dismiss

    func testDemo2KeyboardPushUpAndDismiss() throws {
        // --no-auto-send: keyboard demos must show a STATIC conversation, not a
        // demo auto-send stream racing the push-up (same fix as the UI suite).
        app.launchArguments = ["--seed-messages", "8", "--no-auto-send", "--in-memory"]
        app.launch()

        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        sleep(1)   // let the seeded conversation settle

        tv.tap()   // keyboard up → content pushes up
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            print(">>> SKIP: hardware keyboard")
            return
        }
        XCTAssertTrue(waitForStableLayout(), "Layout did not settle after keyboard show")
        sleep(2)   // hold the pushed-up state

        dismissKeyboard()   // tap the background → keyboard dismisses
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5),
            "Keyboard did not dismiss after background tap")
        XCTAssertTrue(waitForStableLayout(), "Layout did not settle after dismiss")
        sleep(2)   // hold the settled, keyboard-dismissed state
    }

    // MARK: Demo 3 — scrolled away → keyboard does NOT push content

    func testDemo3ScrolledKeyboardNoPushUp() throws {
        // --no-auto-send: keyboard demos must show a STATIC conversation, not a
        // demo auto-send stream racing the push-up (same fix as the UI suite).
        app.launchArguments = ["--seed-messages", "8", "--no-auto-send", "--in-memory"]
        app.launch()

        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        sleep(1)

        scrollUpLargeAmount()   // move away from the bottom (past the threshold)
        sleep(1)

        tv.tap()   // keyboard up, but content is scrolled away → no push
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            print(">>> SKIP: hardware keyboard")
            return
        }
        XCTAssertTrue(waitForStableLayout(), "Layout did not settle after keyboard show")
        sleep(2)   // hold: keyboard up, messages stay put

        dismissKeyboard()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5),
            "Keyboard did not dismiss after background tap")
        sleep(2)   // hold the final state
    }
}
