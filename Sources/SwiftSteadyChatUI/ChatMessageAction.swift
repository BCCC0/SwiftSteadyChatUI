import Foundation

/// The role of a message action — affects styling in the context menu
/// (a `.destructive` action renders red).
public enum ChatMessageActionRole {
    case normal
    case destructive
}

/// A single action in the consumer-defined drop list for a message. The package
/// renders it as the bubble's context menu; the consumer decides the list and
/// handles each action. The handler receives the message's `id`.
public struct ChatMessageAction {
    public let title: String
    public let role: ChatMessageActionRole
    public let handler: (UUID) -> Void

    public init(title: String, role: ChatMessageActionRole = .normal, handler: @escaping (UUID) -> Void) {
        self.title = title
        self.role = role
        self.handler = handler
    }
}

/// Where a `scrollToMessage(id:anchor:)` target is positioned in the viewport.
public enum ScrollAnchor {
    case top
    case center
    case bottom
}
