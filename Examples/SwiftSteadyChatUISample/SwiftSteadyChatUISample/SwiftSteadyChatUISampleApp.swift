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
    let store: ChatMessageStore
    @State private var service: StubChatService?

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
        self.store = store
        // --branch-demo routes to BranchDemoView (two-conversation showcase); the
        // default path keeps the single-conversation demo with its launch args.
        let branchDemo = ProcessInfo.processInfo.arguments.contains("--branch-demo")
        _service = State(initialValue: branchDemo
            ? nil
            : StubChatService.createWithArgs(store: store, conversationId: Self.conversationId))
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
            if ProcessInfo.processInfo.arguments.contains("--branch-demo") {
                BranchDemoView(store: store, config: config)
            } else if let service {
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
}
