import Foundation
import SwiftData

/// Per-conversation prompt metadata. The system prompt is OPAQUE — the package
/// never parses, orders, or interprets it; the consumer constructs whatever string
/// it wants (lorebook/character output) and reads it back to compose the LLM prompt.
@Model
public final class ConversationMeta {
    @Attribute(.unique) public var conversationId: UUID
    public var systemPrompt: String

    public init(conversationId: UUID, systemPrompt: String) {
        self.conversationId = conversationId
        self.systemPrompt = systemPrompt
    }
}
