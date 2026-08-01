import Foundation

/// Display model for a chat message. Mirrors SwiftTavern's MessageItem.
public struct StreamingMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let role: MessageRole
    public var content: String
    public var thinking: String?
    public var streamSource: ChatStreamSource?
    public var isStreamFinished: Bool

    public enum MessageRole: Equatable, Sendable {
        case user
        case assistant
    }

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        thinking: String? = nil,
        streamSource: ChatStreamSource? = nil,
        isStreamFinished: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinking = thinking
        self.streamSource = streamSource
        self.isStreamFinished = isStreamFinished
    }

    public var isUser: Bool { role == .user }

    public var isStreaming: Bool { streamSource != nil && !isStreamFinished }

    public static func == (lhs: StreamingMessage, rhs: StreamingMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.role == rhs.role
            && lhs.content == rhs.content
            && lhs.thinking == rhs.thinking
            && lhs.isStreamFinished == rhs.isStreamFinished
    }
}
