import Testing
@testable import SwiftSteadyChatUI

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
}
