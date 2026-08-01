import Testing
import UIKit
@testable import SwiftSteadyChatUI

/// Serialized: these tests window-host controllers. Swift Testing otherwise
/// runs @MainActor tests concurrently, and two window-hosting suites tearing
/// their retained UIWindows down at once crashes the process ("Cannot form
/// weak reference to instance of class UIWindow ... over-released") — a
/// CI-only flake. Serializing makes window teardown deterministic.
@MainActor
@Suite(.serialized)
final class SyncDiffingTests {
    /// Retains the windows hosting each test's controller so the collection
    /// view is actually on screen (batch updates commit like production, and
    /// the settle loop's re-measure stays consistent with the data source).
    private var windows: [UIWindow] = []

    final class Stub: ChatService {
        var messages: [StreamingMessage] = []
        var onMessagesChanged: (() -> Void)?
        func sendMessage(_ text: String) async {}
    }

    private func makeMessage(_ id: UUID, _ content: String) -> StreamingMessage {
        StreamingMessage(id: id, role: .user, content: content, thinking: nil, streamSource: nil, isStreamFinished: true)
    }

    private func makeLoaded(_ svc: Stub) -> ChatCollectionViewController {
        let vc = ChatCollectionViewController(service: svc)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        windows.append(window)  // keep the window (and the view hierarchy) alive
        _ = vc.view
        return vc
    }

    @Test("append syncs count up via insertItems (no reload)")
    func appendSyncs() {
        let svc = Stub()
        let vc = makeLoaded(svc)
        let a = makeMessage(UUID(), "a")
        let b = makeMessage(UUID(), "b")
        svc.messages = [a]
        svc.onMessagesChanged?()
        #expect(vc.numberOfMessages == 1)
        svc.messages = [a, b]
        svc.onMessagesChanged?()
        #expect(vc.numberOfMessages == 2)
    }

    @Test("delete syncs count down via the non-append path")
    func deleteSyncs() {
        let svc = Stub()
        let vc = makeLoaded(svc)
        let a = makeMessage(UUID(), "a")
        let b = makeMessage(UUID(), "b")
        svc.messages = [a, b]
        svc.onMessagesChanged?()
        svc.messages = [a]
        svc.onMessagesChanged?()
        #expect(vc.numberOfMessages == 1)
    }

    @Test("regenerate (same count, new content) re-measures without reloading")
    func regenerateSyncs() {
        let svc = Stub()
        let vc = makeLoaded(svc)
        let id = UUID()
        svc.messages = [makeMessage(id, "old")]
        svc.onMessagesChanged?()
        svc.messages = [makeMessage(id, "new")]
        svc.onMessagesChanged?()
        #expect(vc.numberOfMessages == 1)
        #expect(vc.messages.first?.content == "new")  // internal messages accessor (see note below)
    }

    @Test("static messages array mid-stream keeps count stable (no reload)")
    func staticMidStream() {
        let svc = Stub()
        let vc = makeLoaded(svc)
        let source = ChatStreamSource()
        let streaming = StreamingMessage(id: UUID(), role: .assistant, content: "", thinking: nil, streamSource: source, isStreamFinished: false)
        svc.messages = [streaming]
        svc.onMessagesChanged?()
        #expect(vc.numberOfMessages == 1)
        svc.messages = [streaming]  // same array — text flows via the source, not the array
        svc.onMessagesChanged?()
        #expect(vc.numberOfMessages == 1)
    }
}
