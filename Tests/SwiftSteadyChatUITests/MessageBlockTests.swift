import Foundation
import Testing
@testable import SwiftSteadyChatUI

@MainActor
@Suite("MessageBlock model")
struct MessageBlockTests {

    private func userPrompt(_ text: String) -> StreamingMessage {
        StreamingMessage(id: UUID(), blocks: [
            .init(kind: .user, content: text, isStreamFinished: true)
        ])
    }

    private func reply(_ blocks: [StreamingMessage.MessageBlock]) -> StreamingMessage {
        StreamingMessage(id: UUID(), blocks: blocks)
    }

    @Test("a user prompt is a single .user block; role derives as .user")
    func userPromptRoleDerivation() {
        let m = userPrompt("hello")
        #expect(m.role == .user)
        #expect(m.isUser)
        #expect(m.isStreamFinished)
    }

    @Test("a reply message is thinking/reply blocks; role derives as .assistant")
    func replyRoleDerivation() {
        let m = reply([
            .init(kind: .thinking, content: "hmm", isStreamFinished: true),
            .init(kind: .reply, content: "answer", isStreamFinished: true),
        ])
        #expect(m.role == .assistant)
        #expect(!m.isUser)
    }

    @Test("message-level isStreamFinished requires every block finished")
    func messageFinishedDerivation() {
        let live = reply([
            .init(kind: .thinking, content: "hmm", isStreamFinished: true),
            .init(kind: .reply, content: "", streamSource: ChatStreamSource(), isStreamFinished: false),
        ])
        #expect(!live.isStreamFinished)
        #expect(live.isStreaming)

        let done = reply([
            .init(kind: .thinking, content: "hmm", isStreamFinished: true),
            .init(kind: .reply, content: "answer", isStreamFinished: true),
        ])
        #expect(done.isStreamFinished)
        #expect(!done.isStreaming)
    }

    @Test("blocks are equal when only the streamSource differs")
    func equatableExcludesSource() {
        let id = UUID()
        let a = StreamingMessage.MessageBlock(id: id, kind: .reply, content: "hi", isStreamFinished: true)
        let b = StreamingMessage.MessageBlock(
            id: id, kind: .reply, content: "hi", streamSource: ChatStreamSource(), isStreamFinished: true
        )
        #expect(a == b)
    }

    @Test("blocks are not equal when kind/content/finish differ")
    func equatableDistinguishesData() {
        let a = StreamingMessage.MessageBlock(kind: .reply, content: "hi", isStreamFinished: true)
        #expect(a != .init(kind: .thinking, content: "hi", isStreamFinished: true))
        #expect(a != .init(kind: .reply, content: "bye", isStreamFinished: true))
        #expect(a != .init(kind: .reply, content: "hi", isStreamFinished: false))
    }

    @Test("Codable round-trip drops streamSource; content/kind/isStreamFinished survive")
    func codableRoundTripDropsSource() throws {
        let source = ChatStreamSource()
        let original = reply([
            .init(kind: .thinking, content: "hmm", streamSource: source, isStreamFinished: true),
            .init(kind: .reply, content: "answer", isStreamFinished: true),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StreamingMessage.self, from: data)
        #expect(decoded.blocks.count == 2)
        #expect(decoded.blocks[0].kind == .thinking)
        #expect(decoded.blocks[0].content == "hmm")
        #expect(decoded.blocks[0].isStreamFinished)
        #expect(decoded.blocks[0].streamSource == nil)  // streamSource is never encoded
        #expect(decoded.blocks[1].content == "answer")
        #expect(decoded.role == .assistant)  // role derives after decode
    }

    @Test("a persisted block can never re-stream after decode")
    func persistedBlockNeverRestreams() throws {
        // Even if a consumer persisted a non-finished block, decode yields no
        // source — the renderer can never go down the live-stream path for it.
        let original = reply([
            .init(kind: .reply, content: "partial", isStreamFinished: false)
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StreamingMessage.self, from: data)
        #expect(decoded.blocks[0].streamSource == nil)
        #expect(decoded.blocks[0].isStreamFinished == false)
    }

    @Test("a finished block with a source renders static, not streamed")
    func finishedWinsOverSource() {
        let finished = StreamingMessage.MessageBlock(
            kind: .reply, content: "done", streamSource: ChatStreamSource(), isStreamFinished: true
        )
        #expect(MessageBlockBubble(block: finished).usesStaticMarkdown)

        let streaming = StreamingMessage.MessageBlock(
            kind: .reply, content: "", streamSource: ChatStreamSource(), isStreamFinished: false
        )
        #expect(!MessageBlockBubble(block: streaming).usesStaticMarkdown)

        let user = StreamingMessage.MessageBlock(kind: .user, content: "hi", isStreamFinished: true)
        #expect(MessageBlockBubble(block: user).usesStaticMarkdown)
    }
}
