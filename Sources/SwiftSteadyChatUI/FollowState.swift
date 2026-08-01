import Foundation

/// Whether the chat auto-scrolls to the bottom on content growth.
///
/// - `following`: the user is at the bottom → auto-scroll active.
/// - `brokenByGesture`: the user dragged/scrolled → auto-scroll off until they
///   return to the bottom.
internal enum FollowState: Equatable {
    case following
    case brokenByGesture

    /// The next state given whether the user is mid-gesture and whether the view
    /// is at the bottom. A gesture ALWAYS breaks the follow; returning to the
    /// bottom (not mid-gesture) re-engages it; otherwise the state is unchanged.
    static func transition(current: FollowState, isInteracting: Bool, isNearBottom: Bool) -> FollowState {
        if isInteracting { return .brokenByGesture }
        if isNearBottom { return .following }
        return current
    }
}
