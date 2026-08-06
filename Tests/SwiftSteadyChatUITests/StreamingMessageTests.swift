import Foundation
import Testing
@testable import SwiftSteadyChatUI

@MainActor
@Suite("StreamingMessage model")
struct StreamingMessageTests {

    @Test("a user message derives role .user, isUser, and is always finished")
    func userDerivation() {
        let m = StreamingMessage(id: UUID(), kind: .user, content: "hello")
        #expect(m.role == .user)
        #expect(m.isUser)
        #expect(m.isStreamFinished)
        #expect(!m.isStreaming)
    }

    @Test("a thinking or reply message derives role .assistant")
    func assistantDerivation() {
        let t = StreamingMessage(id: UUID(), kind: .thinking, content: "hmm", isStreamFinished: true)
        let r = StreamingMessage(id: UUID(), kind: .reply, content: "answer", isStreamFinished: true)
        #expect(t.role == .assistant)
        #expect(!t.isUser)
        #expect(r.role == .assistant)
    }

    @Test("a live reply is streaming until finished")
    func streamingDerivation() {
        let live = StreamingMessage(id: UUID(), kind: .reply, content: "", streamSource: ChatStreamSource())
        #expect(!live.isStreamFinished)
        #expect(live.isStreaming)
        let done = StreamingMessage(id: UUID(), kind: .reply, content: "answer", isStreamFinished: true)
        #expect(done.isStreamFinished)
        #expect(!done.isStreaming)
    }

    @Test("streamSource is excluded from Codable (stored ⟹ finished)")
    func codableExcludesSource() throws {
        let m = StreamingMessage(id: UUID(), kind: .reply, content: "answer",
                                 streamSource: ChatStreamSource(), isStreamFinished: true)
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(StreamingMessage.self, from: data)
        #expect(decoded == m)
        #expect(decoded.streamSource == nil)
    }

    @Test("equality ignores streamSource but respects content and finished")
    func equalityIgnoresSource() {
        let id = UUID()
        let a = StreamingMessage(id: id, kind: .reply, content: "x", streamSource: ChatStreamSource(), isStreamFinished: false)
        let b = StreamingMessage(id: id, kind: .reply, content: "x", streamSource: ChatStreamSource(), isStreamFinished: false)
        #expect(a == b)   // different live sources are equal
        let c = StreamingMessage(id: id, kind: .reply, content: "x", isStreamFinished: true)
        #expect(a != c)   // finished state differs
    }
}
