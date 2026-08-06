import Foundation

/// Display model for one chat bubble. A message is exactly one bubble: a user
/// prompt (`.user`, instant, blue, right), a collapsible thinking card
/// (`.thinking`, left), or a normal markdown reply (`.reply`, left). A thinking
/// reply is TWO messages — the consumer appends `.thinking`, streams it, then
/// appends `.reply` and streams it. At most one message streams at a time, and
/// it is always the last element of `messages`.
public struct StreamingMessage: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var kind: MessageKind
    public var content: String?
    /// Transient in-memory stream — **excluded from Codable**. While live, text
    /// flows here; `content` holds the final text once finished.
    public var streamSource: ChatStreamSource?
    /// Stored finish flag. The public `isStreamFinished` derives from this: a
    /// `.user` message is always finished regardless of the stored flag.
    private var streamFinished: Bool

    public init(
        id: UUID = UUID(),
        kind: MessageKind,
        content: String? = nil,
        streamSource: ChatStreamSource? = nil,
        isStreamFinished: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.streamSource = streamSource
        self.streamFinished = isStreamFinished
    }

    public enum MessageKind: String, Codable, Sendable {
        case user, thinking, reply
    }

    /// The message role — **derived**, not stored. Thinking and reply are
    /// assistant-side. Deliberately NESTED (SwiftTavern exports its own top-level
    /// `MessageRole`; a top-level one would collide in consumer adapters).
    public enum MessageRole: Equatable, Sendable {
        case user
        case assistant
    }

    public var role: MessageRole { kind == .user ? .user : .assistant }
    public var isUser: Bool { role == .user }

    /// A `.user` message is always finished (instant, never streams).
    public var isStreamFinished: Bool { kind == .user || streamFinished }

    /// A thinking/reply message still streaming (drives the settle loop).
    public var isStreaming: Bool { kind != .user && !streamFinished }

    /// Equality ignores `streamSource` (a live stream class, not value data) —
    /// two messages differ only by data: id, kind, content, and finish state.
    public static func == (lhs: StreamingMessage, rhs: StreamingMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.content == rhs.content
            && lhs.isStreamFinished == rhs.isStreamFinished
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, content, isStreamFinished
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(MessageKind.self, forKey: .kind)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        streamSource = nil  // never encoded — transient in-memory stream
        streamFinished = try c.decode(Bool.self, forKey: .isStreamFinished)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encode(streamFinished, forKey: .isStreamFinished)
        // streamSource deliberately not encoded — it is transient in-memory state.
    }
}
