import SwiftStreamingMarkdown
import SwiftUI

// MARK: - Message Bubble

public struct MessageBubbleView: View {
    public let message: StreamingMessage
    public let isInline: Bool

    @State private var thinkingExpanded = false
    @State private var userManuallyCollapsed = false

    public init(message: StreamingMessage, isInline: Bool = false) {
        self.message = message
        self.isInline = isInline
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .user {
                Spacer(minLength: isInline ? 40 : 60)
            }

            VStack(alignment: .trailing, spacing: 4) {
                if message.role == .assistant {
                    // ── Thinking block (collapsible) ──
                    if hasThinking {
                        thinkingBubble
                    }

                    // ── Reply bubble (always visible) ──
                    replyBubble
                } else {
                    // User message
                    Text(message.content)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }

            if message.role == .assistant {
                Spacer(minLength: isInline ? 40 : 60)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isInline ? 0 : 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(message.role == .user ? "user-msg" : "assistant-msg")
    }

    // MARK: - Thinking Bubble

    @ViewBuilder
    private var thinkingBubble: some View {
        VStack(spacing: 0) {
            Button {
                let toggledOn = !thinkingExpanded
                withAnimation(.easeInOut(duration: 0.2)) {
                    thinkingExpanded = toggledOn
                }
                if !toggledOn { userManuallyCollapsed = true }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                    Text("Show thinking")
                        .font(.caption2)
                    Spacer()
                    if message.isStreamFinished {
                        Text("Done thinking")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .rotationEffect(.degrees(thinkingExpanded ? 0 : -90))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // Thinking content — ALWAYS in the view tree so streaming continues
            // even when collapsed. Only visual visibility is conditional.
            thinkingContent
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .opacity(thinkingExpanded ? 1 : 0)
                .frame(maxHeight: thinkingExpanded ? nil : 0)
                .clipped()
                .allowsHitTesting(thinkingExpanded)
        }
        // Thinking block stays collapsed by default. The user taps the toggle to view thinking content.
    }

    @ViewBuilder
    private var thinkingContent: some View {
        if let thinking = message.thinking, !thinking.isEmpty {
            MarkdownView(text: thinking)
                .transition(.identity)
        } else {
            HStack {
                Text("Thinking...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView()
                    .scaleEffect(0.6)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Reply Bubble

    /// Test-visible (not API) AND the reply-bubble's single source of truth for
    /// rendering strategy — `replyBubble` branches on it directly, so the hook
    /// and the actual rendering can never drift apart.
    ///
    /// Finished messages render statically (`MarkdownView`). This MUST take
    /// precedence over the stream branch: a re-created hosting controller
    /// (cache eviction then scroll-back) builds a fresh `StreamedMarkdownView`,
    /// but the message's `streamSource` AsyncStream is already exhausted, so a
    /// live stream would consume nothing and render a blank bubble where
    /// content used to be.
    internal var usesStaticMarkdown: Bool {
        if message.isStreamFinished { return true }
        if message.streamSource != nil { return false }
        return !message.content.isEmpty
    }

    @ViewBuilder
    private var replyBubble: some View {
        if usesStaticMarkdown {
            MarkdownView(text: message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else if let source = message.streamSource {
            StreamedMarkdownView(source: source)  // still streaming → keep the live stream
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
            // Empty placeholder while waiting for reply
            Text("")
                .frame(minHeight: 24)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private var hasThinking: Bool {
        message.thinking != nil
    }
}
