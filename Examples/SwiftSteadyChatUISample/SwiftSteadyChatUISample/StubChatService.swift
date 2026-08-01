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

    /// Pre-fill messages for testing (avoids slow UI-based seeding).
    public func seedMessages(count: Int) {
        for i in 0..<count {
            let text = responsePool[i % responsePool.count]
            messages.append(StreamingMessage(role: .user, content: "Test message \(i + 1)"))
            messages.append(StreamingMessage(
                role: .assistant,
                content: text,
                isStreamFinished: true
            ))
        }
        onMessagesChanged?()
    }

    public func sendMessage(_ text: String) async {
        // Wait for any in-progress stream to finish before processing
        while isStreaming {
            try? await Task.sleep(for: .milliseconds(50))
        }

        // 1. Append user message
        messages.append(StreamingMessage(role: .user, content: text))
        onMessagesChanged?()

        // Brief pause before assistant responds
        try? await Task.sleep(for: .milliseconds(50))

        // 2. Create streaming source + placeholder assistant message
        let source = ChatStreamSource()
        let msgID = UUID()
        messages.append(StreamingMessage(
            id: msgID,
            role: .assistant,
            content: "",
            streamSource: source
        ))
        onMessagesChanged?()

        // 3. Pick a canned response
        let reply = responsePool.randomElement()!

        // 4. Stream reply character-by-character so the animation is visible.
        isStreaming = true
        var accumulated = ""
        for ch in reply {
            accumulated.append(ch)
            source.yield(accumulated)
            try? await Task.sleep(for: .milliseconds(20))
        }
        source.finish()
        isStreaming = false

        // 5. Keep streamSource alive so StreamedMarkdownView persists —
        // no flash from StreamedMarkdownView → MarkdownView switch.
        guard let idx = messages.firstIndex(where: { $0.id == msgID }) else { return }
        messages[idx] = StreamingMessage(
            id: msgID,
            role: .assistant,
            content: reply,
            thinking: nil,
            streamSource: source,
            isStreamFinished: true
        )
        onMessagesChanged?()
    }

    /// Build the service from process launch arguments.
    /// - `--long-reply` → deterministic long markdown reply (streaming tests).
    ///   Composes with `--seed-messages` (seeded pairs use the long reply too).
    /// - `--seed-messages N` → pre-fill N user/assistant pairs for UI tests.
    static func createWithArgs() -> StubChatService {
        let args = ProcessInfo.processInfo.arguments
        let service = args.contains("--long-reply")
            ? StubChatService(responsePool: [StubChatService.longStreamingReply])
            : StubChatService()
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
        "OK, let's think through this systematically. First, the problem: SwiftUI keyboard avoidance resizes the chat container. Second, the solution: move keyboard ownership to UIKit. Third, the result: stable frame, reliable near-bottom math.",
    ]
}
