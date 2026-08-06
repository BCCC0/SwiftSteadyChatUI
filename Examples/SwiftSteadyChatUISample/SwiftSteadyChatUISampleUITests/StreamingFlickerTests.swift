import XCTest

// MARK: - Streaming markdown: no flicker, grows in place

final class StreamingFlickerTests: ChatUITestBase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--long-reply", "--no-text-animation"]
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
        // Tolerance is generous: the held code fence POPs in complete at stream
        // end (~60pt at once) and the follow re-pins ~0.2s later, so the message
        // can momentarily sit up to ~44pt below the input bar top without being
        // a real keyboard-height blank.
        XCTAssertGreaterThan(minGap, -60,
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
        app.launchArguments = ["--seed-messages", "3", "--long-reply", "--no-text-animation"]
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

    /// The scroll view must remain scrollable while a reply is streaming — a
    /// drag away from the bottom is not fought by the auto-follow (the settle
    /// loop stops yanking while the user is interacting). A long seeded
    /// conversation gives real content to scroll.
    func testScrollableDuringStreaming() throws {
        app.terminate()
        app.launchArguments = ["--seed-messages", "8", "--long-reply", "--no-text-animation"]
        app.launch()

        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        tv.tap()
        tv.typeText("hello")
        app.buttons["send-button"].tap()

        // Confirm the stream is mid-flight. The gap is LONGER than the held-fence
        // plateau (~1.2s — the tail is withheld until it closes), so growth is
        // seen even if the first sample lands inside it. A single element query
        // keeps the "No matches found for Element at index N" recycling race
        // exposure minimal.
        guard let last = visibleMessages().last else { XCTFail("No messages"); return }
        let h1 = last.frame.height
        Thread.sleep(forTimeInterval: 1.5)
        let h2 = last.frame.height
        print(">>> stream-growing: last.height \(h1)→\(h2)")
        XCTAssertGreaterThan(h2, h1, "Streaming reply is not growing — the swipe would not be mid-stream")

        let screenHeight = app.frame.height
        let beforeMaxY = last.frame.maxY
        print(">>> pinned: last.maxY \(beforeMaxY) (screen \(screenHeight))")

        // Touch-movement-DOWN swipe (finger 0.3 → 0.7): dragging the content
        // down reveals the earlier messages and drags the streaming reply off
        // the bottom of the screen — breaking the auto-follow.
        scrollUpLargeAmount()

        // The auto-follow must be BROKEN: the streaming message's lower bound is
        // now below the screen (no longer pinned above the input bar). If it
        // scrolled fully off, the element no longer exists — either way it left.
        let afterOffScreen = !last.exists || last.frame.maxY > screenHeight
        print(">>> broke-autoscroll: exists=\(last.exists) maxY=\(last.exists ? String(format: "%.0f", last.frame.maxY) : "gone")")
        XCTAssertTrue(afterOffScreen,
            "Auto-follow was not broken: the streaming message is still on screen")

        // It stays off-screen while the stream continues — no snap-back to the bottom.
        Thread.sleep(forTimeInterval: 1.0)
        let stillOffScreen = !last.exists || last.frame.maxY > screenHeight
        print(">>> still off-screen: exists=\(last.exists)")
        XCTAssertTrue(stillOffScreen, "Auto-follow re-engaged and yanked the message back on screen")
    }

    /// MODE 2 REGRESSION: away from the bottom, the streaming message must NOT
    /// jitter up/down as its height changes. Sampled over the stream window, its
    /// bottom edge (maxY) must be monotonic — the change-driven re-measure
    /// never transiently shrinks the cell (the old 60fps measurement race did).
    func testStreamingMessageNoJitterWhenAwayFromBottom() throws {
        app.terminate()
        app.launchArguments = ["--seed-messages", "8", "--long-reply", "--no-text-animation"]
        app.launch()

        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        tv.tap()
        tv.typeText("hello")
        app.buttons["send-button"].tap()

        // Wait for the stream to be mid-flight. The send inserts the user
        // message and starts the assistant reply; the collection view pins the
        // bottom, so the streaming cell is materialized. (Do NOT wait on a
        // logical count — the lazy collection view only materializes ~4 cells,
        // so waitForMessageCount(18) would never fire.) The h2 > h1 growth
        // check below confirms the stream is actively growing.
        Thread.sleep(forTimeInterval: 2)

        // Scroll a small amount away from the bottom (the streaming message
        // stays visible near the edge).
        scrollUpSmallAmount()

        // Confirm the stream is mid-flight: poll over a window and require the
        // max sampled height to exceed the first. Spans the held-fence plateau
        // (~1.2s) and survives a first sample that lands on a static seeded
        // message (the streaming cell can briefly slip below the viewport after
        // the small scroll). 0.5s interval keeps the "No matches found for
        // Element at index N" recycling-race exposure low.
        guard let firstHeight = visibleMessages().last?.frame.height else {
            XCTFail("No messages"); return
        }
        var grew = false
        var maxHeight = firstHeight
        let growDeadline = Date().addingTimeInterval(3)
        while Date() < growDeadline {
            guard let h = visibleMessages().last?.frame.height else { continue }
            if h > maxHeight { grew = true }
            maxHeight = max(maxHeight, h)
            Thread.sleep(forTimeInterval: 0.5)
        }
        print(">>> stream-growing: first=\(firstHeight) max=\(maxHeight) grew=\(grew)")
        XCTAssertTrue(grew, "Streaming reply never grew over a 3s window — not mid-stream")

        // Re-query visibleMessages().last INSIDE the loop. A captured element
        // re-resolves to a recycled cell once the streaming bubble grows below
        // the viewport (recycling changes the index→cell mapping), falsely
        // reading as a ~300pt maxY "drop." Mode 1 already re-queries each poll.
        var lastMaxY: CGFloat = -1
        var maxDrop: CGFloat = 0
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            guard let streaming = visibleMessages().last else { continue }
            let maxY = streaming.frame.maxY
            if lastMaxY >= 0 { maxDrop = max(maxDrop, lastMaxY - maxY) }
            lastMaxY = maxY
            Thread.sleep(forTimeInterval: 0.2)
        }
        print(">>> mode2: maxY drop over stream = \(maxDrop)pt")
        XCTAssertLessThan(maxDrop, 5,
            "Streaming message jittered: its bottom edge dropped by \(maxDrop)pt while streaming")
    }

    /// MODE 1 SANITY: following at the bottom, the previous message must move
    /// monotonically upward as the reply streams — never jump DOWN. (The
    /// smoothness of the slide is verified visually; this catches the follow
    /// mis-anchoring / content jumping downward.)
    func testPreviousMessageMovesMonotonicallyWhenFollowing() throws {
        app.terminate()
        app.launchArguments = ["--seed-messages", "8", "--long-reply", "--no-text-animation"]
        app.launch()

        let tv = app.textViews["input-textview"]
        XCTAssertTrue(tv.waitForExistence(timeout: 10))
        tv.tap()
        tv.typeText("hello")
        app.buttons["send-button"].tap()

        // Wait for the stream to be mid-flight. The send inserts the user
        // message and starts the assistant reply; the collection view pins the
        // bottom, so the streaming cell is materialized. (Do NOT wait on a
        // logical count — the lazy collection view only materializes ~4 cells,
        // so waitForMessageCount(18) would never fire.) The h2 > h1 growth
        // check below confirms the stream is actively growing.
        Thread.sleep(forTimeInterval: 2)
        // Confirm the stream is mid-flight: poll over a window and require the
        // max sampled height to exceed the first. Spans the held-fence plateau
        // (~1.2s) and survives a first sample that lands on a static seeded
        // message (the streaming cell can briefly slip below the viewport after
        // the small scroll). 0.5s interval keeps the "No matches found for
        // Element at index N" recycling-race exposure low.
        guard let firstHeight = visibleMessages().last?.frame.height else {
            XCTFail("No messages"); return
        }
        var grew = false
        var maxHeight = firstHeight
        let growDeadline = Date().addingTimeInterval(3)
        while Date() < growDeadline {
            guard let h = visibleMessages().last?.frame.height else { continue }
            if h > maxHeight { grew = true }
            maxHeight = max(maxHeight, h)
            Thread.sleep(forTimeInterval: 0.5)
        }
        print(">>> stream-growing: first=\(firstHeight) max=\(maxHeight) grew=\(grew)")
        XCTAssertTrue(grew, "Streaming reply never grew over a 3s window — not mid-stream")

        // The message ABOVE the streaming one. As the reply streams at the
        // bottom, this one moves UP (its maxY decreases); it must never move
        // down (maxY increase) — a broken follow would push it down.
        var lastPrevMaxY: CGFloat = -1
        var maxRise: CGFloat = 0
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let msgs = visibleMessages()
            guard msgs.count >= 2 else { continue }
            let prev = msgs[msgs.count - 2]
            let y = prev.frame.maxY
            if lastPrevMaxY >= 0 { maxRise = max(maxRise, y - lastPrevMaxY) }
            lastPrevMaxY = y
            Thread.sleep(forTimeInterval: 0.2)
        }
        print(">>> mode1: previous message maxY rise = \(maxRise)pt")
        XCTAssertLessThan(maxRise, 5,
            "Previous message jumped DOWN by \(maxRise)pt while following — broken follow")
    }
}
