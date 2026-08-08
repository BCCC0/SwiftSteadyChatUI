import SwiftUI
import SwiftSteadyChatUI

/// `--branch-demo` showcase: TWO conversations sharing one SwiftData store, to
/// prove (a) branching — each chat shows its OWN history keyed by conversationId —
/// and (b) restuff — switching away and back re-hydrates the history from the store.
///
/// Alice is seeded with 2 user/assistant pairs (4 messages); Bob with 5 (10).
/// The switcher recreates the service for the selected conversation, and
/// `StubChatService.init` loads `store.messages(for: conversationId)` — so the UI
/// is stuffed with the persisted history on every entry.
struct BranchDemoView: View {
    let store: ChatMessageStore
    let config: ChatUIConfig

    enum DemoConversation: String, CaseIterable, Identifiable {
        case alice, bob
        var id: String { rawValue }
        var title: String { rawValue == "alice" ? "Alice" : "Bob" }
        var conversationId: UUID {
            rawValue == "alice"
                ? UUID(uuidString: "6F1C5B0A-2D3E-4A5B-8C9D-0E1F2A3B4C5D")!
                : UUID(uuidString: "7F2C6B0B-3E4F-5A6B-9C8D-0E1F2A3B4C5D")!
        }
    }

    @State private var selected: DemoConversation = .alice
    @State private var service: StubChatService?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Conversation", selection: $selected) {
                ForEach(DemoConversation.allCases) { c in
                    Text(c.title).tag(c)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityIdentifier("conversation-switcher")

            if let service {
                VStack(spacing: 0) {
                    StatusBarView(service: service)
                    ChatScreen(service: service, config: config)
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                }
                // Key on the SERVICE's conversationId, not `selected`: the subtree
                // must recreate AFTER `.onChange` swaps the service (a fresh
                // controller hydrating the new conversation's history). Keying on
                // `selected` recreates one render too early, before the service
                // changes, and updateUIViewController is a no-op — so the old
                // controller would keep showing the previous conversation.
                .id(service.conversationId)
            }
        }
        .onAppear {
            // --reset-branch: a hermetic start — clear both demo conversations'
            // records so a fresh seed + send is deterministic and the on-disk store
            // never accumulates across runs (used by the relaunch UI test).
            if ProcessInfo.processInfo.arguments.contains("--reset-branch") {
                try? store.deleteAll(for: DemoConversation.alice.conversationId)
                try? store.deleteAll(for: DemoConversation.bob.conversationId)
            }
            // Seed TWO DISTINCT histories into the shared store (once per launch;
            // --in-memory makes each launch fresh). Distinct content lets the UI
            // test assert the branch by text, not by message count (off-screen
            // cells aren't materialized in the accessibility tree).
            seedIfNeeded(.alice, marker: "Alice", count: 2)
            seedIfNeeded(.bob, marker: "Bob", count: 5)
            service = StubChatService(store: store, conversationId: DemoConversation.alice.conversationId)
        }
        .onChange(of: selected) { _, new in
            // Branch: a NEW service for the selected conversation hydrates its
            // history from the store → the UI is stuffed with that chat's record.
            service = StubChatService(store: store, conversationId: new.conversationId)
        }
    }

    private func seedIfNeeded(_ conversation: DemoConversation, marker: String, count: Int) {
        guard store.messages(for: conversation.conversationId).isEmpty else { return }
        for i in 0..<count {
            try? store.append(
                StreamingMessage(id: UUID(), kind: .user, content: "\(marker) message \(i + 1)", isStreamFinished: true),
                conversationId: conversation.conversationId)
            try? store.append(
                StreamingMessage(id: UUID(), kind: .reply, content: "\(marker) reply \(i + 1)", isStreamFinished: true),
                conversationId: conversation.conversationId)
        }
    }
}
