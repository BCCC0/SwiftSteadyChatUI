import Testing
import Foundation
@testable import SwiftSteadyChatUI

@MainActor
@Test("StreamingMessage isStreaming reflects an active source")
func streamingFlagTracksSource() {
    let source = ChatStreamSource()
    var m = StreamingMessage(id: UUID(), blocks: [
        .init(kind: .reply, content: "", streamSource: source, isStreamFinished: false)
    ])
    #expect(m.isStreaming)
    m = StreamingMessage(id: UUID(), blocks: [
        .init(kind: .reply, content: "done", isStreamFinished: true)
    ])
    #expect(!m.isStreaming)
}

@MainActor
@Test("ChatService is a @MainActor protocol type")
func serviceProtocolExists() {
    final class Stub: ChatService {
        var messages: [StreamingMessage] = []
        var onMessagesChanged: (() -> Void)?
        func sendMessage(_ text: String) async {}
    }
    #expect(Stub().messages.isEmpty)
}
