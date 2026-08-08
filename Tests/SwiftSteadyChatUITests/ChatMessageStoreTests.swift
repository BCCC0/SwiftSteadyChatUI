import Foundation
import SwiftData
import Testing
@testable import SwiftSteadyChatUI

@MainActor
@Suite("ChatMessageStore")
struct ChatMessageStoreTests {

    private func makeStore() throws -> ChatMessageStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MessageRecord.self, ConversationMeta.self, configurations: config)
        return ChatMessageStore(modelContainer: container)
    }

    @Test("append + messages(for:) returns the ordered full history, conversation-scoped")
    func historyRoundTrip() throws {
        let store = try makeStore()
        let cid = UUID()
        try store.append(StreamingMessage(id: UUID(), kind: .user, content: "hi", isStreamFinished: true), conversationId: cid)
        let reply = StreamingMessage(id: UUID(), kind: .reply, content: "hello", isStreamFinished: true)
        try store.append(reply, conversationId: cid)
        // A different conversation must not leak in.
        try store.append(StreamingMessage(id: UUID(), kind: .user, content: "other", isStreamFinished: true), conversationId: UUID())

        let history = store.messages(for: cid)
        #expect(history.count == 2)
        #expect(history[0].content == "hi")
        #expect(history[1].content == "hello")
        #expect(history[0].streamSource == nil)   // re-entry hydration: sources are nil
    }

    @Test("replace finalizes a streaming placeholder in place (stored ⟹ finished)")
    func replaceFinalizes() throws {
        let store = try makeStore()
        let cid = UUID()
        let id = UUID()
        try store.append(StreamingMessage(id: id, kind: .reply, content: "", isStreamFinished: false), conversationId: cid)
        try store.replace(StreamingMessage(id: id, kind: .reply, content: "final", thinking: "hmm", isStreamFinished: true), conversationId: cid)
        let history = store.messages(for: cid)
        #expect(history.count == 1)
        #expect(history[0].content == "final")
        #expect(history[0].thinking == "hmm")
        #expect(history[0].isStreamFinished)
    }

    @Test("mid-list delete keeps the remaining order at the store level")
    func midListDelete() throws {
        let store = try makeStore()
        let cid = UUID()
        let a = UUID(); let b = UUID(); let c = UUID()
        try store.append(StreamingMessage(id: a, kind: .user, content: "A", isStreamFinished: true), conversationId: cid)
        try store.append(StreamingMessage(id: b, kind: .user, content: "B", isStreamFinished: true), conversationId: cid)
        try store.append(StreamingMessage(id: c, kind: .user, content: "C", isStreamFinished: true), conversationId: cid)
        try store.delete(id: b, conversationId: cid)
        #expect(store.messages(for: cid).map(\.content) == ["A", "C"])
    }

    @Test("deleteAll clears the conversation")
    func deleteAllClears() throws {
        let store = try makeStore()
        let cid = UUID()
        try store.append(StreamingMessage(id: UUID(), kind: .user, content: "hi", isStreamFinished: true), conversationId: cid)
        try store.deleteAll(for: cid)
        #expect(store.messages(for: cid).isEmpty)
    }

    @Test("systemPrompt is opaque metadata: set + get back")
    func systemPromptMetadata() throws {
        let store = try makeStore()
        let cid = UUID()
        #expect(store.systemPrompt(for: cid) == nil)
        try store.setSystemPrompt("You are a pirate.", conversationId: cid)
        #expect(store.systemPrompt(for: cid) == "You are a pirate.")
        try store.setSystemPrompt("You are a ninja.", conversationId: cid)
        #expect(store.systemPrompt(for: cid) == "You are a ninja.")
    }
}
