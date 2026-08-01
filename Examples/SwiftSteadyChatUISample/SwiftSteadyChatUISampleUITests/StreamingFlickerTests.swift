import XCTest

// MARK: - Streaming markdown: no flicker, grows in place

final class StreamingFlickerTests: ChatUITestBase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--long-reply"]
        app.launch()
    }

    /// The core claim: the streaming assistant bubble grows in place and
    /// is NEVER recreated (the collection view must not reload mid-stream).
    /// Asserted by sampling the bubble across the whole stream:
    ///   • it exists continuously (never disappears → no view recreation)
    ///   • its height is non-decreasing (content only grows, never resets)
    ///   • it grows by a meaningful amount (streaming actually happened)
    ///   • after the stream ends it settles at the max height (no post-stream flicker)
    func testStreamingBubbleGrowsInPlaceWithoutFlicker() throws {
        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        tv.tap()
        tv.typeText("hello")
        app.buttons["send-button"].tap()

        let assistant = assistantMessage()
        XCTAssertTrue(assistant.waitForExistence(timeout: 10), "Assistant bubble never appeared")

        // Sample every ~80ms across the stream (~250 chars @ 20ms ≈ 5s, so the
        // full window comfortably covers it).
        var heights: [CGFloat] = []
        var missingStreak = 0
        var maxMissingStreak = 0
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if assistant.exists {
                missingStreak = 0
                let h = assistant.frame.height
                if h > 2 { heights.append(h) } // skip pre-layout zero frames
            } else {
                missingStreak += 1
                maxMissingStreak = max(maxMissingStreak, missingStreak)
            }
            Thread.sleep(forTimeInterval: 0.08)
        }

        XCTAssertLessThan(maxMissingStreak, 3,
            "Bubble disappeared for \(maxMissingStreak) consecutive samples — view was recreated (flicker)")

        XCTAssertGreaterThan(heights.count, 5, "Too few samples of the bubble: \(heights.count)")

        // Largest single-sample drop. A view recreation resets the rendered
        // content and drops the height by a lot; healthy growth never drops.
        var maxDrop: CGFloat = 0
        for i in 1..<heights.count {
            let drop = heights[i - 1] - heights[i]
            if drop > maxDrop { maxDrop = drop }
        }
        print(">>> stream heights: first=\(heights.first ?? -1) max=\(heights.max() ?? -1) last=\(heights.last ?? -1) maxDrop=\(maxDrop) samples=\(heights.count)")
        XCTAssertLessThan(maxDrop, 5,
            "Bubble height dropped by \(maxDrop)pt during streaming — content reset (flicker)")

        guard let first = heights.first, let maxH = heights.max() else { return }
        XCTAssertGreaterThan(maxH - first, 20,
            "Bubble grew only \(maxH - first)pt — streaming may not have rendered incrementally")

        let settled = heights.last ?? maxH
        XCTAssertLessThan(abs(settled - maxH), 5,
            "Bubble shrank \(abs(settled - maxH))pt after streaming finished — post-stream flicker")
    }

    /// With the keyboard up, the streaming reply must stay bottom-anchored just
    /// above the input bar the whole time — never occluded by the keyboard,
    /// never floating above a blank. Samples the gap throughout the stream.
    func testStreamingWithKeyboardUpStaysAboveInputBar() throws {
        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        tv.tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            print(">>> SKIP: hardware keyboard")
            return
        }

        tv.typeText("hello")
        app.buttons["send-button"].tap()

        // Send dismisses the keyboard; re-show it so the stream runs with the
        // keyboard up (the point of this test).
        tv.tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            print(">>> SKIP: hardware keyboard")
            return
        }

        let assistant = assistantMessage()
        XCTAssertTrue(assistant.waitForExistence(timeout: 10), "Assistant bubble never appeared")

        var gaps: [CGFloat] = []
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if assistant.exists, let barTop = inputBarTop() {
                let gap = barTop - assistant.frame.maxY
                gaps.append(gap)
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        XCTAssertGreaterThan(gaps.count, 5, "Too few gap samples: \(gaps.count)")

        let minGap = gaps.min() ?? .greatestFiniteMagnitude
        let maxGap = gaps.max() ?? .leastNormalMagnitude
        print(">>> stream-with-keyboard gap range: \(minGap)...\(maxGap) (samples=\(gaps.count))")

        // Never occluded (message below the input bar top → negative gap).
        XCTAssertGreaterThan(minGap, -40,
            "Streaming message occluded by keyboard (min gap=\(minGap))")
        // Never a keyboard-height blank (~300pt) — bottom-anchored throughout.
        XCTAssertLessThan(maxGap, 100,
            "Streaming message floated above a blank (max gap=\(maxGap))")
    }

    /// Seeded long content + keyboard: the no-scroll-into-blank guard also holds
    /// while a stream is in flight (drag up during streaming must not reveal a
    /// blank below the message).
    func testNoScrollIntoBlankDuringStreaming() throws {
        app.terminate()
        app.launchArguments = ["--seed-messages", "3", "--long-reply"]
        app.launch()

        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        tv.tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            print(">>> SKIP: hardware keyboard")
            return
        }

        tv.typeText("hello")
        app.buttons["send-button"].tap()

        // The streaming reply is the LAST message (this conversation is seeded,
        // so `assistantMessage()` (firstMatch) would hit a seeded one up-screen).
        XCTAssertTrue(assistantMessage().waitForExistence(timeout: 10), "Assistant bubble never appeared")
        guard let assistant = visibleMessages().last else {
            XCTFail("No messages")
            return
        }

        // Give the stream a moment to start, then drag up into the reserve.
        Thread.sleep(forTimeInterval: 0.5)
        let beforeY = assistant.frame.maxY
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        from.press(forDuration: 0.2, thenDragTo: to)

        XCTAssertTrue(waitForStableLayout(timeout: 30), "Layout did not settle after drag")
        let afterY = assistant.frame.maxY
        let movedUp = beforeY - afterY
        print(">>> drag-during-stream: lastMaxY \(beforeY)→\(afterY) movedUp=\(movedUp)pt")

        XCTAssertLessThan(movedUp, 50,
            "Drag during streaming revealed a blank: last message moved \(movedUp)pt up")
    }

    /// Standard chat UX: sending a prompt dismisses the keyboard.
    func testKeyboardDismissesOnSend() throws {
        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        tv.tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            print(">>> SKIP: hardware keyboard")
            return
        }

        tv.typeText("hello")
        app.buttons["send-button"].tap()

        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5),
            "Keyboard did not dismiss after sending a prompt")
    }
}
