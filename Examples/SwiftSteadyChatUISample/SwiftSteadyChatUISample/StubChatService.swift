import Foundation
import Observation
import SwiftSteadyChatUI

@MainActor
@Observable
public final class StubChatService: ChatService {
    public private(set) var messages: [StreamingMessage] = []
    public private(set) var isStreaming = false
    public var onMessagesChanged: (() -> Void)?

    private let responsePool: [String]
    private let charDelayMs: UInt64

    public init(responsePool: [String]? = nil, charDelayMs: UInt64 = 20) {
        self.responsePool = responsePool ?? StubChatService.defaultPool
        self.charDelayMs = charDelayMs
    }

    /// Deterministic long markdown reply for streaming tests (`--long-reply`).
    /// Multi-paragraph, bold, list, and a code block — exercises the streaming
    /// markdown path over several seconds (~250 chars @ 20ms ≈ 5s).
    public static let longStreamingReply = """
    Here's a **longer** streaming reply with markdown formatting.

    * Bullet one with some text that wraps across multiple lines nicely
    * Bullet two continues the list with more content
    * Bullet three keeps the bubble growing

    ```swift
    let answer = 42
    print("streaming works")
    ```

    And a final paragraph so the bubble keeps growing tall enough to exercise
    the streaming render path for a few seconds.
    """

    /// A genuinely huge markdown reply for stress-demoing the streaming render
    /// path (`--longest-reply`). Built programmatically so we don't bloat the
    /// source with a literal: ~48k chars across many paragraphs, lists, code
    /// blocks, headings, and a table. At 20ms/char this streams for ~16 minutes,
    /// but the point is to watch render cost grow as the document does.
    public static var longestStreamingReply: String {
        var out = "# Streaming Stress Test\n\n"
        for section in 0..<160 {
            out += "## Section \(section)\n\n"
            out += "This is paragraph one of section \(section). It contains enough "
            out += "prose to force the bubble to wrap and re-measure as the document "
            out += "grows, exercising the incremental render path.\n\n"
            out += "Paragraph two **with bold** and `inline code` and a [link](https://example.com) "
            out += "plus some *emphasis* to vary the inline styling.\n\n"
            out += "* bullet one\n* bullet two\n* bullet three\n\n"
            out += "```swift\nfunc render(_ section: Int) -> String {\n"
            out += "    return \"section \\(section) code block\"\n}\n```\n\n"
        }
        out += "| A | B | C |\n|---|---|---|\n| 1 | 2 | 3 |\n\n"
        out += "## Finale\n\nA closing paragraph to end the document.\n"
        return out
    }

    /// Pre-fill messages for testing (avoids slow UI-based seeding).
    public func seedMessages(count: Int) {
        for i in 0..<count {
            let text = responsePool[i % responsePool.count]
            messages.append(StreamingMessage(id: UUID(), blocks: [
                .init(kind: .user, content: "Test message \(i + 1)", isStreamFinished: true)
            ]))
            messages.append(StreamingMessage(id: UUID(), blocks: [
                .init(kind: .reply, content: text, isStreamFinished: true)
            ]))
        }
        onMessagesChanged?()
    }

    public func sendMessage(_ text: String) async {
        // Wait for any in-progress stream to finish before processing
        while isStreaming {
            try? await Task.sleep(for: .milliseconds(50))
        }

        // 1. Instant user prompt (Class 1)
        messages.append(StreamingMessage(id: UUID(), blocks: [
            .init(kind: .user, content: text, isStreamFinished: true)
        ]))
        onMessagesChanged?()

        // Brief pause before assistant responds
        try? await Task.sleep(for: .milliseconds(50))

        // 2. Reply (Class 2) — one streaming reply block
        let reply = responsePool.randomElement()!
        let replySource = ChatStreamSource()
        let msgID = UUID()
        messages.append(StreamingMessage(id: msgID, blocks: [
            .init(kind: .reply, content: "", streamSource: replySource, isStreamFinished: false)
        ]))
        onMessagesChanged?()

        // 3. Stream reply character-by-character so the animation is visible.
        isStreaming = true
        var accumulated = ""
        for ch in reply {
            accumulated.append(ch)
            replySource.yield(accumulated)
            try? await Task.sleep(for: .milliseconds(charDelayMs))
        }
        replySource.finish()
        isStreaming = false

        // 4. Replace with finished blocks — stored ⟹ finished; source kept alive
        // so a kept controller's stream view shows the final text (no flash).
        guard let idx = messages.firstIndex(where: { $0.id == msgID }) else { return }
        messages[idx] = StreamingMessage(id: msgID, blocks: [
            .init(kind: .reply, content: reply, streamSource: replySource, isStreamFinished: true)
        ])
        onMessagesChanged?()
    }

    /// Build the service from process launch arguments.
    /// - `--long-reply` → deterministic long markdown reply (streaming tests).
    ///   Composes with `--seed-messages` (seeded pairs use the long reply too).
    /// - `--seed-messages N` → pre-fill N user/assistant pairs for UI tests.
    static func createWithArgs() -> StubChatService {
        let args = ProcessInfo.processInfo.arguments
        let service: StubChatService
        if args.contains("--longest-reply") {
            // ~48k chars at 1ms/char ≈ 48s. At that pace the markdown re-parse
            // (which grows with document size) outruns the 1ms yield — so the
            // bubble visibly falls behind the stream, demonstrating the
            // full-re-parse cost scaling. Use this for the stress demo.
            service = StubChatService(responsePool: [StubChatService.longestStreamingReply], charDelayMs: 1)
        } else if args.contains("--long-reply") {
            service = StubChatService(responsePool: [StubChatService.longStreamingReply])
        } else {
            service = StubChatService()
        }
        if let idx = args.firstIndex(of: "--seed-messages"),
           let countStr = args.dropFirst(idx + 1).first,
           let count = Int(countStr) {
            service.seedMessages(count: count)
        }
        return service
    }

    private static let defaultPool: [String] = [
        "Got it! Here's a longer response so you can test the scroll behavior. The keyboard layout guide should push the content up smoothly when near the bottom.",
        "That's an interesting point. Let me think about this for a moment. The key insight is that we need the collection view frame to stay completely stable while the keyboard animates.",
        "Here's a multi-line response.\n\n* First, the keyboard avoids the VStack\n* Second, we use contentInset instead\n* Third, the scroll view frame never changes\n\nThis keeps distanceFromBottom accurate.",
        "Testing testing. This message has enough text to wrap across multiple lines so you can verify the bubble sizing is working correctly with different content lengths.",
        "I see what you mean. The push-up automation uses two mechanisms: the `keyboardLayoutGuide` for the input bar and `contentInset.bottom` for the scroll view.",
        "Let me explain the architecture in more detail:\n\n```swift\n// The input bar is pinned to the keyboard guide\ninputBar.bottomAnchor.constraint(\n    equalTo: view.keyboardLayoutGuide.topAnchor\n)\n```\n\nThis means UIKit handles all keyboard animation automatically.",
        "Here's a short one.",
        "OK, let's think through this systematically. First, the problem: SwiftUI keyboard avoidance resizes the chat container. Second, the solution: move keyboard ownership to UIKit. Third, the result: stable frame, reliable near-bottom math."
    ]
}
