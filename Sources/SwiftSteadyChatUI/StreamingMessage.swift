import Foundation

/// Display model for a chat message. Mirrors SwiftTavern's MessageItem.
///
/// A message is an ordered list of independent `MessageBlock`s in two classes:
/// - a **user prompt**: a single `.user` block (instant, static, blue bubble);
/// - a **reply**: only `.thinking`/`.reply` blocks (streaming markdown).
public struct StreamingMessage: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var blocks: [MessageBlock]

    public init(id: UUID = UUID(), blocks: [MessageBlock]) {
        self.id = id
        self.blocks = blocks
    }

    /// The message role — **derived**, not stored. A message containing a
    /// `.user` block is a user prompt; otherwise it's a reply.
    public var role: MessageRole { blocks.contains { $0.kind == .user } ? .user : .assistant }
    public var isUser: Bool { role == .user }

    /// Every block finished ⟺ the message finished (drives eviction/settle).
    public var isStreamFinished: Bool { blocks.allSatisfy(\.isStreamFinished) }

    /// Any block still streaming (drives the settle loop).
    public var isStreaming: Bool { blocks.contains { !$0.isStreamFinished } }

    public enum MessageRole: Equatable, Sendable {
        case user
        case assistant
    }

    /// One bubble's worth of content. Thinking and reply share this type — only
    /// `kind` differs. A `.user` block never streams and is finished from birth.
    public struct MessageBlock: Identifiable, Equatable, Sendable, Codable {
        public let id: UUID
        public var kind: BlockKind
        public var content: String?
        /// Transient in-memory stream — **excluded from Codable**. While a block
        /// is live, text flows here; `content` holds the final text once finished.
        public var streamSource: ChatStreamSource?
        public var isStreamFinished: Bool

        public init(
            id: UUID = UUID(),
            kind: BlockKind,
            content: String? = nil,
            streamSource: ChatStreamSource? = nil,
            isStreamFinished: Bool = false
        ) {
            self.id = id
            self.kind = kind
            self.content = content
            self.streamSource = streamSource
            self.isStreamFinished = isStreamFinished
        }

        private enum CodingKeys: String, CodingKey {
            case id, kind, content, isStreamFinished
        }

        public static func == (lhs: MessageBlock, rhs: MessageBlock) -> Bool {
            lhs.id == rhs.id
                && lhs.kind == rhs.kind
                && lhs.content == rhs.content
                && lhs.isStreamFinished == rhs.isStreamFinished
            // streamSource excluded — it's a live stream class, not value data.
        }
    }

    public enum BlockKind: Sendable, Codable {
        case thinking
        case reply
        case user
    }

    public static func == (lhs: StreamingMessage, rhs: StreamingMessage) -> Bool {
        lhs.id == rhs.id && lhs.blocks == rhs.blocks
    }
}
