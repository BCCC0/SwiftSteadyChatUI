import Foundation
import CoreGraphics

/// Behavior/appearance knobs for the chat UI layer.
public struct ChatUIConfig: Sendable {
    /// How a streaming (live) message renders its markdown while it arrives.
    public enum StreamingMode: Sendable {
        /// Plain text while streaming; fades into rendered markdown on finish.
        /// Flicker-free by construction, but no live markdown formatting.
        case antiFlicker
        /// Live streaming markdown in a fixed-but-expandable window. Shows
        /// markdown as it streams; some re-render flicker for complex markdown.
        case streamingMarkdown
        /// TEMP Q1 comparison: live streaming markdown with NO locked window —
        /// `StreamedMarkdownView` self-sizes directly. Only used to judge whether
        /// the fixed-but-expandable container is required.
        case streamingMarkdownUnlocked
    }

    /// Dismiss the keyboard when the user sends a message (default `true`).
    public var dismissKeyboardOnSend: Bool
    /// Show the scroll-to-bottom button (default `true`).
    public var showsScrollToBottomButton: Bool
    /// Vertical spacing between message bubbles (points).
    /// Default `8` = the validated source's `minimumLineSpacing`; changing it
    /// alters the validated layout the UI tests were verified against.
    public var messageSpacing: CGFloat
    /// Settle-loop tolerances (see `ChatCollectionViewController`).
    public var settleMaxTicks: Int
    public var settleStableTicks: Int
    public var settleTolerance: CGFloat
    /// How streaming messages render while text arrives (default `.antiFlicker`).
    public var streamingMode: StreamingMode

    public init(
        dismissKeyboardOnSend: Bool = true,
        showsScrollToBottomButton: Bool = true,
        messageSpacing: CGFloat = 8,
        settleMaxTicks: Int = 24,
        settleStableTicks: Int = 5,
        settleTolerance: CGFloat = 0.5,
        streamingMode: StreamingMode = .antiFlicker
    ) {
        self.dismissKeyboardOnSend = dismissKeyboardOnSend
        self.showsScrollToBottomButton = showsScrollToBottomButton
        self.messageSpacing = messageSpacing
        self.settleMaxTicks = settleMaxTicks
        self.settleStableTicks = settleStableTicks
        self.settleTolerance = settleTolerance
        self.streamingMode = streamingMode
    }
}
