import SwiftData
import SwiftUI
import SwiftSteadyChatUI

@main
struct SwiftSteadyChatUISampleApp: App {
    /// The single demo conversation's fixed id — the source-of-truth identity.
    /// In a real consumer this is the `ChatConversation.id`, created once and
    /// stable for the conversation's lifetime. `force_unwrapping` is disabled in
    /// this repo's lint config, so the `!` on a literal constant is lint-safe.
    private static let conversationId = UUID(uuidString: "6F1C5B0A-2D3E-4A5B-8C9D-0E1F2A3B4C5D")!

    let container: ModelContainer
    @State private var service: StubChatService

    init() {
        // UI tests launch with `--in-memory` so each run is hermetic (the fixed
        // conversationId would otherwise cross-contaminate the on-disk store).
        let inMemory = ProcessInfo.processInfo.arguments.contains("--in-memory")
        do {
            container = try ModelContainer(
                for: MessageRecord.self, ConversationMeta.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")   // lint-safe (no try!)
        }
        let store = ChatMessageStore(modelContainer: container)
        let service = StubChatService.createWithArgs(store: store, conversationId: Self.conversationId)
        _service = State(initialValue: service)
    }

    /// UI automation launches with `--no-text-animation` to exercise the stable
    /// (non-animated) streaming render; the default demo keeps the word fade-in.
    private var config: ChatUIConfig {
        let args = ProcessInfo.processInfo.arguments
        var c = ChatUIConfig()
        if args.contains("--no-text-animation") { c.streamingAnimateText = false }
        return c
    }

    var body: some Scene {
        WindowGroup {
            // The demo composes a consumer-owned pinned band above the chat
            // (StatusBarView — plain SwiftUI wired to StubChatService), showing
            // the "pinned content above the chat" pattern. The package provides
            // no screen-chrome hooks; the consumer declares the height and
            // renders whatever it likes.
            VStack(spacing: 0) {
                StatusBarView(service: service)
                ChatScreen(service: service, config: config)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .task {
                // Demo helper (`--auto-thinking`): auto-send a prompt shortly
                // after launch so the thinking block streams on its own.
                guard let prompt = service.autoSendText else { return }
                try? await Task.sleep(for: .milliseconds(900))
                await service.sendMessage(prompt)
            }
        }
    }
}
