import Foundation
import CoreGraphics

/// Behavior/appearance knobs for the chat UI layer.
public struct ChatUIConfig: Sendable {
    /// Dismiss the keyboard when the user sends a message (default `true`).
    public var dismissKeyboardOnSend: Bool
    /// Show the scroll-to-bottom button (default `true`).
    public var showsScrollToBottomButton: Bool
    /// Vertical spacing between message bubbles (points).
    /// Default `8` = the validated source's `minimumLineSpacing`; changing it
    /// alters the validated layout the UI tests were verified against.
    public var messageSpacing: CGFloat
    /// Fade streamed text words in one-by-one while streaming (default `true`).
    /// The UI automation suite launches the sample with `--no-text-animation`
    /// to exercise the stable (non-animated) render.
    public var streamingAnimateText: Bool
    /// Settle-loop tolerances (see `ChatCollectionViewController`).
    public var settleMaxTicks: Int
    public var settleStableTicks: Int
    public var settleTolerance: CGFloat

    public init(
        dismissKeyboardOnSend: Bool = true,
        showsScrollToBottomButton: Bool = true,
        messageSpacing: CGFloat = 8,
        streamingAnimateText: Bool = true,
        settleMaxTicks: Int = 24,
        settleStableTicks: Int = 5,
        settleTolerance: CGFloat = 0.5
    ) {
        self.dismissKeyboardOnSend = dismissKeyboardOnSend
        self.showsScrollToBottomButton = showsScrollToBottomButton
        self.messageSpacing = messageSpacing
        self.streamingAnimateText = streamingAnimateText
        self.settleMaxTicks = settleMaxTicks
        self.settleStableTicks = settleStableTicks
        self.settleTolerance = settleTolerance
    }
}
