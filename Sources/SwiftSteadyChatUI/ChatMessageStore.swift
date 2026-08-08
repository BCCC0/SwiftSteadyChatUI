import Foundation
import SwiftData

/// The package's SwiftData store — the durable source of truth for the chat record
/// (message stream + opaque system-prompt metadata). The consumer writes finished
/// messages here when a stream ends and reads them back on re-entry. It never
/// drives the live UI (the render path runs on the consumer's in-memory array).
@MainActor
public final class ChatMessageStore {
    public let modelContainer: ModelContainer
    public var modelContext: ModelContext { modelContainer.mainContext }

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: History

    public func messages(for conversationId: UUID) -> [StreamingMessage] {
        let descriptor = FetchDescriptor<MessageRecord>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.order)]
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        return records.map { record in
            record.toStreamingMessage() ?? StreamingMessage(
                id: record.id, kind: .reply, content: record.content,
                isStreamFinished: record.isStreamFinished)
        }
    }

    public func append(_ message: StreamingMessage, conversationId: UUID) throws {
        modelContext.insert(MessageRecord(
            id: message.id, conversationId: conversationId, kind: message.kind,
            content: message.content, thinking: message.thinking, timestamp: message.timestamp,
            isStreamFinished: message.isStreamFinished, order: nextOrder(for: conversationId)))
        try modelContext.save()
    }

    /// Finalize a message in place (content + finished state), or append if absent.
    public func replace(_ message: StreamingMessage, conversationId: UUID) throws {
        let descriptor = FetchDescriptor<MessageRecord>(predicate: #Predicate { $0.id == message.id })
        if let record = try modelContext.fetch(descriptor).first {
            record.content = message.content
            record.thinking = message.thinking
            record.timestamp = message.timestamp
            record.isStreamFinished = message.isStreamFinished
            try modelContext.save()
        } else {
            try append(message, conversationId: conversationId)
        }
    }

    public func delete(id: UUID, conversationId: UUID) throws {
        let descriptor = FetchDescriptor<MessageRecord>(predicate: #Predicate { $0.id == id })
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    public func deleteAll(for conversationId: UUID) throws {
        let descriptor = FetchDescriptor<MessageRecord>(
            predicate: #Predicate { $0.conversationId == conversationId })
        for record in try modelContext.fetch(descriptor) { modelContext.delete(record) }
        try modelContext.save()
    }

    // MARK: System prompt metadata

    public func systemPrompt(for conversationId: UUID) -> String? {
        let descriptor = FetchDescriptor<ConversationMeta>(
            predicate: #Predicate { $0.conversationId == conversationId })
        return (try? modelContext.fetch(descriptor))?.first?.systemPrompt
    }

    public func setSystemPrompt(_ prompt: String, conversationId: UUID) throws {
        let descriptor = FetchDescriptor<ConversationMeta>(
            predicate: #Predicate { $0.conversationId == conversationId })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.systemPrompt = prompt
        } else {
            modelContext.insert(ConversationMeta(conversationId: conversationId, systemPrompt: prompt))
        }
        try modelContext.save()
    }

    /// Next display order = max existing + 1. (Using `fetchCount` would collide
    /// with a surviving record's `order` after a mid-list delete — max+1 never does.)
    private func nextOrder(for conversationId: UUID) -> Int {
        let descriptor = FetchDescriptor<MessageRecord>(
            predicate: #Predicate { $0.conversationId == conversationId })
        let records = (try? modelContext.fetch(descriptor)) ?? []
        return (records.map(\.order).max() ?? -1) + 1
    }
}
