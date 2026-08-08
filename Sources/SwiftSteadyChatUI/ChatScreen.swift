import SwiftUI

/// SwiftUI wrapper over `ChatCollectionViewController` for embedding the
/// chat UI layer in a SwiftUI app.
public struct ChatScreen: UIViewControllerRepresentable {
    private let service: any ChatService
    private let config: ChatUIConfig
    private let messageActions: ((ChatCollectionViewController, StreamingMessage) -> [ChatMessageAction])?

    public init(service: any ChatService, config: ChatUIConfig = .init(),
                messageActions: ((ChatCollectionViewController, StreamingMessage) -> [ChatMessageAction])? = nil) {
        self.service = service
        self.config = config
        self.messageActions = messageActions
    }

    /// The consumer-defined drop list: the package renders it as each bubble's
    /// context menu; the consumer decides the actions and handles each.
    public func messageActions(
        _ actions: @escaping (ChatCollectionViewController, StreamingMessage) -> [ChatMessageAction]
    ) -> ChatScreen {
        ChatScreen(service: service, config: config, messageActions: actions)
    }

    public func makeUIViewController(context: Context) -> ChatCollectionViewController {
        let vc = ChatCollectionViewController(service: service, config: config)
        vc.messageActions = messageActions
        return vc
    }

    public func updateUIViewController(_ uiViewController: ChatCollectionViewController, context: Context) {
        uiViewController.messageActions = messageActions
    }
}
