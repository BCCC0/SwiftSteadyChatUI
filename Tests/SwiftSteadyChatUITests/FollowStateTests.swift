import Testing
@testable import SwiftSteadyChatUI

@MainActor
@Suite("FollowState")
struct FollowStateTests {

    @Test("a gesture always breaks the follow")
    func gestureBreaks() {
        #expect(FollowState.transition(current: .following, isInteracting: true, isNearBottom: true) == .brokenByGesture)
        #expect(FollowState.transition(current: .brokenByGesture, isInteracting: true, isNearBottom: true) == .brokenByGesture)
    }

    @Test("returning to the bottom re-engages the follow")
    func returnToBottomReengages() {
        #expect(FollowState.transition(current: .brokenByGesture, isInteracting: false, isNearBottom: true) == .following)
    }

    @Test("away from the bottom keeps the follow broken")
    func awayStaysBroken() {
        #expect(FollowState.transition(current: .brokenByGesture, isInteracting: false, isNearBottom: false) == .brokenByGesture)
    }

    @Test("at the bottom and not interacting stays following")
    func atBottomStaysFollowing() {
        #expect(FollowState.transition(current: .following, isInteracting: false, isNearBottom: true) == .following)
    }

    // The WIRING, not just the pure transition: a gesture that returns to the
    // bottom re-engages the follow through the scroll delegate. Regression for
    // the dead-re-engage bug (the last scroll tick runs mid-gesture, so without
    // the end-callbacks the follow stays broken after a return-to-bottom).
    @Test("a drag that returns to the bottom re-engages the follow via the scroll delegate")
    func dragReturnReengages() {
        final class Stub: ChatService {
            var messages: [StreamingMessage] = []
            var onMessagesChanged: (() -> Void)?
            func sendMessage(_ text: String) async {}
        }
        let controller = ChatCollectionViewController(service: Stub())
        controller.followState = .brokenByGesture
        // Drag toward the bottom (scrollViewDidScroll keeps it broken mid-drag),
        // then the touch ends AT the bottom with no momentum — re-engage.
        controller.scrollViewWillBeginDragging(controller.collectionView)
        controller.scrollViewDidEndDragging(controller.collectionView, willDecelerate: false)
        #expect(controller.followState == .following)
    }
}
