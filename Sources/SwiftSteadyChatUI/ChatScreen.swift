import SwiftUI

/// SwiftUI wrapper over `ChatCollectionViewController` for embedding the
/// chat UI layer in a SwiftUI app.
public struct ChatScreen: UIViewControllerRepresentable {
    private let service: any ChatService
    private let config: ChatUIConfig

    public init(service: any ChatService, config: ChatUIConfig = .init()) {
        self.service = service
        self.config = config
    }

    public func makeUIViewController(context: Context) -> ChatCollectionViewController {
        ChatCollectionViewController(service: service, config: config)
    }

    public func updateUIViewController(_ uiViewController: ChatCollectionViewController, context: Context) {}
}
