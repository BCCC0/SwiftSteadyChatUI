import XCTest

// MARK: - Base for the recording-only demo tests
//
// These demos are pacing vehicles for VIDEO RECORDING, not regression tests —
// the real assertions live in `SwiftSteadyChatUISampleUITests`. They live in a
// SEPARATE bundle (`SwiftSteadyChatUISampleDemoUITests`) that is NOT part of
// the `SwiftSteadyChatUISample` scheme's test action, so the normal suite is
// untouched (still exactly 12 tests). Record them with:
//
//   xcodebuild test -project .../SwiftSteadyChatUISample.xcodeproj \
//     -scheme SwiftSteadyChatUISampleDemo \
//     -destination 'platform=iOS Simulator,name=iPhone 17' \
//     -only-testing:SwiftSteadyChatUISampleDemoUITests/DemoRecordingTests/<test> \
//     -skipMacroValidation
//
// The helpers mirror `ChatUITestBase` (same semantics) so the demos drive the
// app identically to the real suite. If the main suite's helpers change, keep
// these in sync.

class DemoUITestBase: XCTestCase {
    let app = XCUIApplication()

    func dismissKeyboard() {
        let topOfScreen = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        topOfScreen.tap()
    }

    /// Message bubbles sorted top-to-bottom by accessibility identifier.
    func visibleMessages() -> [XCUIElement] {
        let user = app.descendants(matching: .any).matching(identifier: "user-msg").allElementsBoundByIndex
        let assistant = app.descendants(matching: .any).matching(identifier: "assistant-msg").allElementsBoundByIndex
        return (user + assistant).filter { $0.exists }.sorted { $0.frame.minY < $1.frame.minY }
    }

    func assistantMessage() -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "assistant-msg").firstMatch
    }

    /// Polls until the last message and keyboard are both stable (layout settled).
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

    /// Scroll up well past the 100pt near-bottom threshold.
    func scrollUpLargeAmount() {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let to   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        from.press(forDuration: 0.3, thenDragTo: to)
        sleep(1)
    }
}
