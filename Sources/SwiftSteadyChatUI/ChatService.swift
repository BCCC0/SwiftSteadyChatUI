import Foundation

/// The one required seam between your app and the chat UI layer.
///
/// Conform your app's chat service to this protocol and hand it to
/// `ChatCollectionViewController`/`ChatScreen`. The UI layer observes
/// `messages` and calls `sendMessage(_:)`; the service streams text via
/// `ChatStreamSource` (see `MessageBlock.streamSource`).
@MainActor
public protocol ChatService: AnyObject {
    /// The current message list. **Must stay static mid-stream** — text flows
    /// through each streaming message's `streamSource`, and the array is only
    /// replaced (never mutated in place) while a message is streaming.
    var messages: [StreamingMessage] { get }
    /// Called by the UI when it needs to re-sync the list.
    var onMessagesChanged: (() -> Void)? { get set }
    /// Sends a user message and begins the assistant reply stream.
    func sendMessage(_ text: String) async
}
