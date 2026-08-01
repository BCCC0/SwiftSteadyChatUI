import Testing
import Foundation
@testable import SwiftSteadyChatUI

@MainActor
final class CacheEvictionTests {
    final class StubService: ChatService {
        var messages: [StreamingMessage]
        var onMessagesChanged: (() -> Void)?
        init(messages: [StreamingMessage]) { self.messages = messages }
        func sendMessage(_ text: String) async {}
    }

    private func makeFinished(_ n: Int) -> StreamingMessage {
        StreamingMessage(id: UUID(), role: .assistant, content: "msg \(n)", thinking: nil, streamSource: nil, isStreamFinished: true)
    }

    @Test("finished messages beyond the eviction window release their hosting controller")
    func evictsFinishedFarMessages() {
        let svc = StubService(messages: (0..<200).map { makeFinished($0) })
        let vc = ChatCollectionViewController(service: svc)
        _ = vc.view
        svc.onMessagesChanged?()
        vc.debugWarmCacheForAllMessages()      // force-populate all 200 (visible cells alone would keep this ~10-15 and pass the assertion vacuously)
        #expect(vc.debugCachedControllerCount == 200)  // pre-condition: cache fully warm
        vc.debugCompleteSettle()               // runs settleTick -> evictCachedControllers()
        #expect(vc.debugCachedControllerCount <= 100)  // bounded below 200 after eviction
    }
}
