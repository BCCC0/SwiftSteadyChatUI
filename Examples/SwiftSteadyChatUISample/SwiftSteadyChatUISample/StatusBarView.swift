import SwiftUI

/// Consumer-owned pinned top band — demonstrates the "pinned content above the
/// chat" pattern. The consumer declares the band's height and renders whatever
/// it likes; the package's `ChatScreen` stays an opaque full-screen chat below.
///
/// Deliberately NOT part of the package: it's plain SwiftUI wired to the
/// consumer's own `StubChatService`, proving the band can read live chat state
/// (streaming status flips "Ready" → "Assistant is typing…") AND drive the app
/// (the Clear button calls the service and empties the conversation).
struct StatusBarView: View {
    let service: StubChatService

    private var isStreaming: Bool {
        service.messages.last?.isStreaming ?? false
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isStreaming ? Color.orange : Color.green)
                .frame(width: 8, height: 8)

            if isStreaming {
                ProgressView().controlSize(.small)
                Text("Assistant is typing…").font(.caption)
            } else {
                Text("Ready").font(.caption)
            }

            Spacer()

            Button("Clear") {
                service.clearChat()
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("banner-clear-button")
        }
        .padding(.horizontal, 12)
        .frame(height: 40) // the consumer declares the band's height
        .background(.thinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("status-bar")
    }
}
