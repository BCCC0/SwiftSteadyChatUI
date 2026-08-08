import Foundation
import SwiftData
import Testing
@testable import SwiftSteadyChatUI

@MainActor
@Suite("Store schema")
struct StoreSchemaTests {

    @Test("MessageRecord maps to StreamingMessage (finished)")
    func recordToStreamingMessage() throws {
        let record = MessageRecord(
            id: UUID(), conversationId: UUID(),
            kind: .reply, content: "answer", thinking: "hmm",
            timestamp: Date(timeIntervalSince1970: 5), isStreamFinished: true, order: 0)
        let msg = record.toStreamingMessage()
        try #require(msg != nil)
        #expect(msg?.kind == .reply)
        #expect(msg?.content == "answer")
        #expect(msg?.thinking == "hmm")
        #expect(msg?.isStreamFinished == true)
        #expect(msg?.streamSource == nil)   // streamSource is never stored
    }

    @Test("MessageRecord persists in an in-memory container")
    func recordPersists() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MessageRecord.self, ConversationMeta.self, configurations: config)
        let context = container.mainContext
        let conversationId = UUID()
        context.insert(MessageRecord(id: UUID(), conversationId: conversationId, kind: .user,
                                     content: "hi", thinking: nil, timestamp: nil, isStreamFinished: true, order: 0))
        try context.save()
        let descriptor = FetchDescriptor<MessageRecord>(
            predicate: #Predicate { $0.conversationId == conversationId })
        #expect(try context.fetch(descriptor).count == 1)
    }

    @Test("ConversationMeta stores an opaque system prompt")
    func metaStoresPrompt() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MessageRecord.self, ConversationMeta.self, configurations: config)
        let context = container.mainContext
        let conversationId = UUID()
        context.insert(ConversationMeta(conversationId: conversationId, systemPrompt: "You are a pirate."))
        try context.save()
        let descriptor = FetchDescriptor<ConversationMeta>(
            predicate: #Predicate { $0.conversationId == conversationId })
        #expect(try context.fetch(descriptor).first?.systemPrompt == "You are a pirate.")
    }
}
