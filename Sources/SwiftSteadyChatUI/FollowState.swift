import Foundation

/// Whether the chat auto-scrolls to the bottom on content growth.
///
/// This is a LOGICAL state, not a geometric one — there is no "near the bottom"
/// threshold. The follow breaks on any gesture and re-engages only on an
/// explicit user action (send a prompt, tap the scroll-to-bottom FAB).
///
/// - `following`: auto-scroll active.
/// - `brokenByGesture`: a gesture broke it; off until an explicit re-engage.
internal enum FollowState: Equatable {
    case following
    case brokenByGesture

    /// The event that moves the state machine.
    internal enum Event {
        /// A user drag/scroll gesture — breaks the follow instantly.
        case gestureBegan
        /// An explicit user action to return to the stream (send a prompt, tap
        /// the scroll-to-bottom FAB) — re-engages and pins the bottom.
        case reengage
    }

    /// The next state for an event. A gesture ALWAYS breaks; a re-engage ALWAYS
    /// re-follows. No geometric condition participates.
    static func transition(current: FollowState, event: Event) -> FollowState {
        switch (current, event) {
        case (_, .gestureBegan): return .brokenByGesture
        case (_, .reengage): return .following
        }
    }
}
