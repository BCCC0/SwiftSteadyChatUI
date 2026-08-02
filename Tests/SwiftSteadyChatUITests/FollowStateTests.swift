import Testing
@testable import SwiftSteadyChatUI

@MainActor
@Suite("FollowState")
struct FollowStateTests {

    @Test("a gesture always breaks the follow")
    func gestureBreaks() {
        #expect(FollowState.transition(current: .following, event: .gestureBegan) == .brokenByGesture)
        #expect(FollowState.transition(current: .brokenByGesture, event: .gestureBegan) == .brokenByGesture)
    }

    @Test("an explicit re-engage always re-follows")
    func reengageRefollows() {
        #expect(FollowState.transition(current: .brokenByGesture, event: .reengage) == .following)
        #expect(FollowState.transition(current: .following, event: .reengage) == .following)
    }

    // The WIRING: a drag breaks the follow; an explicit re-engage (the FAB
    // scroll-to-bottom) re-follows. There is NO geometric re-engage — returning
    // to the bottom does not re-attach (that is the design's key simplification).
    @Test("a drag breaks the follow and the FAB re-engages it")
    func dragBreaksAndFABReengages() {
        final class Stub: ChatService {
            var messages: [StreamingMessage] = []
            var onMessagesChanged: (() -> Void)?
            func sendMessage(_ text: String) async {}
        }
        let controller = ChatCollectionViewController(service: Stub())
        controller.followState = .following
        controller.scrollViewWillBeginDragging(controller.collectionView)
        #expect(controller.followState == .brokenByGesture)
        controller.didTapScrollToBottom()
        #expect(controller.followState == .following)
    }
}
