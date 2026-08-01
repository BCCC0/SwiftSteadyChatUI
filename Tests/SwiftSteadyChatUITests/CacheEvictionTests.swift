import Testing
import Foundation
import UIKit
@testable import SwiftSteadyChatUI

@MainActor
final class CacheEvictionTests {
    /// Retains the windows hosting each test's controller so the collection
    /// view has a real on-screen bounds. The eviction window (±2000 pt around
    /// the visible rect) is only meaningful window-hosted: off-screen the
    /// bounds are zero-width, every finished controller is evicted, and the
    /// bounded-cache assertion passes vacuously.
    private var windows: [UIWindow] = []

    final class StubService: ChatService {
        var messages: [StreamingMessage]
        var onMessagesChanged: (() -> Void)?
        init(messages: [StreamingMessage]) { self.messages = messages }
        func sendMessage(_ text: String) async {}
    }

    private func makeFinished(_ n: Int) -> StreamingMessage {
        StreamingMessage(id: UUID(), role: .assistant, content: "msg \(n)", thinking: nil, streamSource: nil, isStreamFinished: true)
    }

    /// A finished message whose `streamSource` is an already-exhausted
    /// AsyncStream — exactly what a re-created controller hits after cache
    /// eviction + scroll-back. The non-nil source matters: a message with a
    /// nil source already renders statically, so it would not catch the
    /// blank-bubble regression.
    private func makeFinishedWithDeadStream(_ n: Int) -> StreamingMessage {
        let source = ChatStreamSource()
        source.yield("msg \(n)")
        source.finish()
        return StreamingMessage(id: UUID(), role: .assistant, content: "msg \(n)", thinking: nil, streamSource: source, isStreamFinished: true)
    }

    private func makeLoaded(_ svc: StubService) -> ChatCollectionViewController {
        let vc = ChatCollectionViewController(service: svc)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        windows.append(window)  // keep the window (and the view hierarchy) alive
        _ = vc.view
        return vc
    }

    @Test("finished messages beyond the eviction window release their hosting controller")
    func evictsFinishedFarMessages() {
        let svc = StubService(messages: (0..<200).map { makeFinished($0) })
        let vc = makeLoaded(svc)
        svc.onMessagesChanged?()
        vc.debugWarmCacheForAllMessages()      // force-populate all 200 (visible cells alone would keep this ~10-15 and pass the assertion vacuously)
        #expect(vc.debugCachedControllerCount == 200)  // pre-condition: cache fully warm
        vc.debugCompleteSettle()               // runs settleTick -> evictCachedControllers()
        // Window-hosted, the eviction window is meaningful: finished messages
        // near the visible rect stay cached while far ones are released —
        // bounded below the full 200, but not zero.
        #expect(vc.debugCachedControllerCount < 200)
        #expect(vc.debugCachedControllerCount > 0)
    }

    @Test("finished message re-created after cache eviction renders static markdown, not a dead stream")
    func recreatedFinishedMessageRendersStaticMarkdown() {
        let svc = StubService(messages: (0..<200).map { makeFinishedWithDeadStream($0) })
        let vc = makeLoaded(svc)
        svc.onMessagesChanged?()
        vc.debugWarmCacheForAllMessages()      // warm every controller (200)
        #expect(vc.debugCachedControllerCount == 200)
        vc.debugCompleteSettle()               // evict finished messages beyond the window

        // Re-create a controller for a finished message whose cached one was
        // just evicted — exactly what hostingController(for:) does when the
        // user scrolls back into a long chat. The recreated bubble must render
        // the final content statically (MarkdownView), NOT a fresh
        // StreamedMarkdownView: the streamSource stream is already finished, so
        // StreamedMarkdownController.start()'s `for await` yields nothing and
        // the bubble would render blank where content used to be.
        let last = vc.messages[199]
        let recreated = vc.hostingController(for: last)
        #expect(recreated.rootView.usesStaticMarkdown)
    }
}
