import Foundation
import Observation
import SwiftSteadyChatUI

@MainActor
@Observable
public final class StubChatService: ChatService {
    public private(set) var messages: [StreamingMessage] = []
    public private(set) var isStreaming = false
    public var onMessagesChanged: (() -> Void)?

    /// When true, `sendMessage` streams a `.thinking` block before the reply
    /// (launch arg `--thinking-reply`). Demonstrates the streamed-thinking fix.
    public var streamsThinking = false

    /// When set, the app auto-sends this prompt on launch (demo only — launch
    /// arg `--auto-thinking`). Lets you watch the thinking block stream and
    /// toggle it by hand without typing.
    public var autoSendText: String?

    /// Deterministic thinking text — streams before the reply under
    /// `--thinking-reply`. The UI test waits for the "Let me reason" prefix.
    public static let thinkingText = """
    Let me reason through this.

    The user sent a prompt, so I need to figure out what they actually want,
    weigh the constraints, and only then produce the final reply.
    """

    private let store: ChatMessageStore
    let conversationId: UUID
    private let responsePool: [String]
    private let charDelayMs: UInt64

    public init(
        store: ChatMessageStore,
        conversationId: UUID,
        responsePool: [String]? = nil,
        charDelayMs: UInt64 = 20
    ) {
        self.store = store
        self.conversationId = conversationId
        self.responsePool = responsePool ?? StubChatService.defaultPool
        self.charDelayMs = charDelayMs
        // Hydrate on re-entry: restore the persisted history for this
        // conversation (the store is the durable source of truth; sources nil
        // → static render).
        messages = store.messages(for: conversationId)
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

    /// A syntax-dense markdown reply for judging streaming reflow flicker
    /// (`--rich-reply`). Packs the block types that historically reflow worst
    /// while streaming — headings, a table, nested lists, a blockquote, code
    /// blocks, and heavy inline styling — so each re-render has real layout
    /// churn to either reflow (flicker) or re-fill a locked height (stable).
    public static let richStreamingReply = """
    # Heading One — a big title

    ## Heading Two with **bold** inside

    A paragraph with **bold**, *italic*, ***bold italic***, `inline code`, a
    [link](https://example.com), and ~~strikethrough~~ to stress inline reflow.

    > A blockquote with *emphasis* and `code` inside, spanning enough lines to
    > force the block to wrap and re-measure as the stream grows taller.

    1. First ordered item with **bold text** that wraps across lines
    2. Second ordered item with `inline code`
       - a nested bullet under the ordered item
       - another nested bullet that keeps going
    3. Third ordered item with a [link](https://example.com)

    * Unordered item one with a [link](https://example.com)
    * Unordered item two with *italic* styling
    * Unordered item three with **bold**

    | Column A | Column B | Column C |
    |---|---|---|
    | alpha | **bold** | `code` |
    | beta | *italic* | more text |

    ```swift
    func flickerCheck(_ markdown: String) -> Bool {
        let rendered = renderer.parse(markdown)
        return rendered.isStable
    }
    ```

    ---

    ### Heading Three with a list

    - bullet with *emphasis*
    - bullet with `code` and a [link](https://example.com)

    And a final paragraph that keeps growing so the reveal keeps stepping
    downward to the very end of the document.
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

    /// Pre-fill messages for testing (avoids slow UI-based seeding). Seeds
    /// persist to the store too, so a re-entry restores the seeded history.
    public func seedMessages(count: Int) {
        for i in 0..<count {
            let text = responsePool[i % responsePool.count]
            let userMessage = StreamingMessage(
                id: UUID(), kind: .user, content: "Test message \(i + 1)", isStreamFinished: true
            )
            let replyMessage = StreamingMessage(
                id: UUID(), kind: .reply, content: text, isStreamFinished: true
            )
            messages.append(userMessage)
            messages.append(replyMessage)
            try? store.append(userMessage, conversationId: conversationId)
            try? store.append(replyMessage, conversationId: conversationId)
        }
        onMessagesChanged?()
    }

    /// Seed a conversation for the thinking-toggle UI test (`--seed-thinking`):
    /// a NORMAL assistant reply, a user prompt, then a thinking + reply PAIR as
    /// two separate messages (all messages FINISHED — the post-stream state).
    /// The thinking message is the 3rd of 4, with a finished reply below it — the
    /// test toggles the thinking bubble and checks its expand/collapse status
    /// against the message above it (deterministic — nothing streams underneath).
    public func seedThinkingConversation() {
        let seeded: [StreamingMessage] = [
            StreamingMessage(id: UUID(), kind: .reply, content: "Seeded normal reply", isStreamFinished: true),
            StreamingMessage(id: UUID(), kind: .user, content: "Seed prompt", isStreamFinished: true),
            StreamingMessage(id: UUID(), kind: .thinking, content: StubChatService.thinkingText, isStreamFinished: true),
            StreamingMessage(id: UUID(), kind: .reply, content: StubChatService.longStreamingReply, isStreamFinished: true)
        ]
        for message in seeded {
            messages.append(message)
            try? store.append(message, conversationId: conversationId)
        }
        onMessagesChanged?()
    }

    public func sendMessage(_ text: String) async {
        // Wait for any in-progress stream to finish before processing
        while isStreaming {
            try? await Task.sleep(for: .milliseconds(50))
        }

        // 1. Instant user prompt (right-aligned blue).
        let userMessage = StreamingMessage(
            id: UUID(), kind: .user, content: text, isStreamFinished: true
        )
        messages.append(userMessage)
        try? store.append(userMessage, conversationId: conversationId)
        onMessagesChanged?()
        try? await Task.sleep(for: .milliseconds(50))

        isStreaming = true
        defer { isStreaming = false }

        // 2. Thinking block (separate collapsible bubble, streams first).
        if streamsThinking {
            let thinkingID = UUID()
            let thinkingSource = ChatStreamSource()
            messages.append(StreamingMessage(
                id: thinkingID, kind: .thinking, content: "", streamSource: thinkingSource, isStreamFinished: false
            ))
            onMessagesChanged?()
            var acc = ""
            for ch in StubChatService.thinkingText {
                acc.append(ch)
                thinkingSource.yield(acc)
                try? await Task.sleep(for: .milliseconds(charDelayMs))
            }
            thinkingSource.finish()
            // Replace with the finished message — stored ⟹ finished; source kept alive.
            let finishedThinking = StreamingMessage(
                id: thinkingID, kind: .thinking, content: acc, streamSource: thinkingSource, isStreamFinished: true
            )
            if let idx = messages.firstIndex(where: { $0.id == thinkingID }) {
                messages[idx] = finishedThinking
            }
            try? store.replace(finishedThinking, conversationId: conversationId)
            onMessagesChanged?()
        }

        // 3. Reply block (separate bubble, streams after the thinking finishes).
        let reply = responsePool.randomElement()!
        let replyID = UUID()
        let replySource = ChatStreamSource()
        messages.append(StreamingMessage(
            id: replyID, kind: .reply, content: "", streamSource: replySource, isStreamFinished: false
        ))
        onMessagesChanged?()
        var acc = ""
        for ch in reply {
            acc.append(ch)
            replySource.yield(acc)
            try? await Task.sleep(for: .milliseconds(charDelayMs))
        }
        replySource.finish()
        // Replace with the finished message — stored ⟹ finished; source kept alive.
        let finishedReply = StreamingMessage(
            id: replyID, kind: .reply, content: acc, streamSource: replySource, isStreamFinished: true
        )
        if let idx = messages.firstIndex(where: { $0.id == replyID }) {
            messages[idx] = finishedReply
        }
        try? store.replace(finishedReply, conversationId: conversationId)
        onMessagesChanged?()
    }

    /// Consumer-side action for the demo's status bar: empties the conversation
    /// through the service seam. Demonstrates that a consumer-owned top band can
    /// DRIVE the app, not just observe it. Idle-only — a mid-stream clear would
    /// orphan the in-flight send task (its reply would never re-appear).
    public func clearChat() {
        guard !isStreaming else { return }
        messages = []
        try? store.deleteAll(for: conversationId)
        onMessagesChanged?()
    }

    /// Build the service from process launch arguments.
    /// - `--long-reply` → deterministic long markdown reply (streaming tests).
    ///   Composes with `--seed-messages` (seeded pairs use the long reply too).
    /// - `--seed-messages N` → pre-fill N user/assistant pairs for UI tests.
    static func createWithArgs(store: ChatMessageStore, conversationId: UUID) -> StubChatService {
        let args = ProcessInfo.processInfo.arguments
        let service: StubChatService
        if args.contains("--seed-thinking") {
            service = StubChatService(store: store, conversationId: conversationId)
            service.seedThinkingConversation()
        } else if args.contains("--auto-thinking") {
            // Slower char delay (40ms) so the thinking stream is easy to watch
            // and toggle by hand. Auto-sends on launch (see the sample App).
            service = StubChatService(store: store, conversationId: conversationId, responsePool: [StubChatService.longStreamingReply], charDelayMs: 40)
            service.streamsThinking = true
            service.autoSendText = "Show me how you think."
        } else if args.contains("--rich-reply") {
            // Syntax-dense markdown at a watchable pace (~35ms/char ≈ 18s):
            // headings, table, nested lists, blockquote, code blocks. Auto-sends
            // so the stream starts without typing.
            service = StubChatService(store: store, conversationId: conversationId, responsePool: [StubChatService.richStreamingReply], charDelayMs: 35)
            service.autoSendText = "Render complex markdown"
        } else if args.contains("--thinking-reply") {
            service = StubChatService(store: store, conversationId: conversationId, responsePool: [StubChatService.longStreamingReply])
            service.streamsThinking = true
        } else if args.contains("--longest-reply") {
            // ~48k chars at 1ms/char ≈ 48s. At that pace the markdown re-parse
            // (which grows with document size) outruns the 1ms yield — so the
            // bubble visibly falls behind the stream, demonstrating the
            // full-re-parse cost scaling. Use this for the stress demo.
            service = StubChatService(store: store, conversationId: conversationId, responsePool: [StubChatService.longestStreamingReply], charDelayMs: 1)
        } else if args.contains("--long-reply") {
            service = StubChatService(store: store, conversationId: conversationId, responsePool: [StubChatService.longStreamingReply])
        } else {
            // Default launch (no args): demonstrate the thinking block.
            // `streamsThinking` makes every reply stream a thinking block first,
            // and `autoSendText` auto-sends a prompt shortly after launch (see
            // the sample App) so the streamed thinking + toggle is visible
            // immediately — no launch args needed.
            service = StubChatService(store: store, conversationId: conversationId)
            service.streamsThinking = true
            service.autoSendText = "Show me how you think."
        }
        if let idx = args.firstIndex(of: "--seed-messages"),
           let countStr = args.dropFirst(idx + 1).first,
           let count = Int(countStr) {
            service.seedMessages(count: count)
        }
        // UI tests opt out of the demo auto-send so keyboard measurements run
        // against a static conversation (the auto-send streaming bubble otherwise
        // races every measurement — see docs/superpowers/reports/2026-08-05-ui-test-failures.md).
        // Default launches (no args) still auto-send for the demo.
        if args.contains("--no-auto-send") {
            service.autoSendText = nil
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
