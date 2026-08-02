import Testing
import Foundation
import UIKit
@testable import SwiftSteadyChatUI

/// TEMP PROOF (not a permanent suite): 10x the history must NOT scale the live
/// hosting-controller set 10x. The cache is bounded by the visible window
/// (`bounds.insetBy(dx: 0, dy: -2000)` in `evictCachedControllers`), so after
/// settling, ~the same number of controllers survive for 100 and 1000 messages.
@MainActor
@Suite(.serialized)
final class LongHistoryScaleTests {
    /// Static, process-lifetime: same rationale as CacheEvictionTests — retained
    /// windows must never deallocate mid-run (CI over-release crash).
    private static var windows: [UIWindow] = []

    final class StubService: ChatService {
        var messages: [StreamingMessage]
        var onMessagesChanged: (() -> Void)?
        init(messages: [StreamingMessage]) { self.messages = messages }
        func sendMessage(_ text: String) async {}
    }

    private func makeFinished(_ n: Int) -> StreamingMessage {
        StreamingMessage(id: UUID(), blocks: [
            .init(kind: .reply, content: "msg \(n)", isStreamFinished: true)
        ])
    }

    private func measureLiveCount(after total: Int) -> Int {
        let svc = StubService(messages: (0..<total).map { makeFinished($0) })
        let vc = ChatCollectionViewController(service: svc)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        Self.windows.append(window)
        _ = vc.view
        svc.onMessagesChanged?()
        vc.debugWarmCacheForAllMessages()   // force-populate ALL — worst case
        #expect(vc.debugCachedControllerCount == total)
        vc.debugCompleteSettle()            // settleTick + evictCachedControllers
        return vc.debugCachedControllerCount
    }

    @Test("long history: live controllers are bounded by the visible window, not the total")
    func liveCacheIsBoundedRegardlessOfHistoryLength() {
        let cached100 = measureLiveCount(after: 100)
        let cached1000 = measureLiveCount(after: 1000)

        print(">>> long-history: total=100 cached-after-settle=\(cached100)")
        print(">>> long-history: total=1000 cached-after-settle=\(cached1000)")

        // Neither scales with the total — both are ~the visible window (≈90 at
        // ~50pt rows inside ±2000pt). 10x history must not mean 10x live views.
        #expect(cached100 > 0)
        #expect(cached100 < 200)
        #expect(cached1000 > 0)
        #expect(cached1000 < 200)
        #expect(cached1000 < cached100 * 4, "live set should be window-bounded, not proportional to history")
    }
}
