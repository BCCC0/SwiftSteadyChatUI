import Foundation
import SwiftData
import Testing
import UIKit
@testable import SwiftSteadyChatUI

@MainActor
@Suite("Per-message controller APIs", .serialized)
struct MessageActionApiTests {
    /// Retains the windows hosting each test's controller so the collection view
    /// has real bounds and batch updates commit. Static (process-lifetime), like
    /// CacheEvictionTests — a UIWindow torn down while UIKit still holds a weak
    /// ref to it crashes with "Cannot form weak reference to instance of class
    /// UIWindow ... over-released" (a CI-only flake).
    private static var windows: [UIWindow] = []

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

    private func makeStore() throws -> ChatMessageStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MessageRecord.self, ConversationMeta.self, configurations: config)
        return ChatMessageStore(modelContainer: container)
    }

    private func makeLoaded(_ svc: StubService) -> ChatCollectionViewController {
        let vc = ChatCollectionViewController(service: svc, config: .init())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = vc
        window.makeKeyAndVisible()   // fires viewDidLoad → mirror = svc.messages
        Self.windows.append(window)  // process-lifetime: never deallocated mid-run
        return vc
    }

    @Test("deleteMessage removes the correct row from the mirror and the store (mid-list)")
    func deleteMessageRemovesRowAndRecord() throws {
        let store = try makeStore()
        let cid = UUID()
        let a = UUID(); let b = UUID(); let c = UUID()
        let msgs = [
            StreamingMessage(id: a, kind: .user, content: "A", isStreamFinished: true),
            StreamingMessage(id: b, kind: .user, content: "B", isStreamFinished: true),
            StreamingMessage(id: c, kind: .user, content: "C", isStreamFinished: true)
        ]
        for m in msgs { try store.append(m, conversationId: cid) }

        // Window-hosted: the deleteItems batch actually commits.
        let vc = makeLoaded(StubService(messages: msgs))

        vc.deleteMessage(id: b, conversationId: cid, store: store)

        // Correct row: A and C survive, B is gone (not the tail).
        #expect(vc.messages.map(\.id) == [a, c])
        // The durable record is gone too.
        #expect(store.messages(for: cid).map(\.id) == [a, c])
    }

    @Test("deleteMessage is a no-op for an unknown id")
    func deleteMessageUnknownId() throws {
        let store = try makeStore()
        let cid = UUID()
        let vc = makeLoaded(StubService(messages: [
            StreamingMessage(id: UUID(), kind: .user, content: "A", isStreamFinished: true)
        ]))
        vc.deleteMessage(id: UUID(), conversationId: cid, store: store)   // no-op, no crash
        #expect(vc.messages.count == 1)
    }
}
