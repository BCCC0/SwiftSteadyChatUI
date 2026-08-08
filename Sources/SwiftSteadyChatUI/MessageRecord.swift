import Foundation
import SwiftData

/// Persisted message record — the package's SwiftData store is the durable source
/// of truth for the chat record. Only finished display state is stored
/// (`stored ⟹ finished`); `streamSource` is never a stored field.
@Model
public final class MessageRecord {
    @Attribute(.unique) public var id: UUID
    public var conversationId: UUID
    public var kindRaw: String
    public var content: String?
    public var thinking: String?
    public var timestamp: Date?
    public var isStreamFinished: Bool
    public var order: Int

    public init(
        id: UUID,
        conversationId: UUID,
        kind: StreamingMessage.MessageKind,
        content: String?,
        thinking: String?,
        timestamp: Date?,
        isStreamFinished: Bool,
        order: Int
    ) {
        self.id = id
        self.conversationId = conversationId
        self.kindRaw = kind.rawValue
        self.content = content
        self.thinking = thinking
        self.timestamp = timestamp
        self.isStreamFinished = isStreamFinished
        self.order = order
    }
}
