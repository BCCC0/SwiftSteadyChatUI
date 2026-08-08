import Foundation
import Testing
@testable import SwiftSteadyChatUI

@MainActor
@Suite("Per-message controller APIs")
struct MessageActionApiTests {

    /// Minimal ChatService fake (matches the existing test pattern in CacheEvictionTests).
    private final class StubService: ChatService {
        var messages: [StreamingMessage]
        var onMessagesChanged: (() -> Void)?
        init(messages: [StreamingMessage] = []) { self.messages = messages }
        func sendMessage(_ text: String) async {}
    }

    @Test("scrollToMessage breaks the follow so a jump sticks")
    func scrollToMessageBreaksFollow() {
        let id = UUID()
        let vc = ChatCollectionViewController(service: StubService(), config: .init())
        vc.loadViewIfNeeded()
        vc.messages = [StreamingMessage(id: id, kind: .reply, content: "B", isStreamFinished: true)]
        vc.scrollToMessage(id: id, anchor: .center)
        #expect(vc.followState == .brokenByGesture,
            "A jump is a navigation away from the bottom — the follow must break or the next stream yanks the view back")
    }

    @Test("scrollToMessage with an unknown id is a no-op and does not break the follow")
    func scrollToMessageUnknownId() {
        let vc = ChatCollectionViewController(service: StubService(), config: .init())
        vc.loadViewIfNeeded()
        vc.messages = [StreamingMessage(id: UUID(), kind: .user, content: "A", isStreamFinished: true)]
        vc.scrollToMessage(id: UUID(), anchor: .top)   // unknown → no-op, no crash
        #expect(vc.followState == .following, "An unknown-id jump is a no-op and must not break the follow")
    }
}
