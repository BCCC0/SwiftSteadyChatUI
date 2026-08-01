import SwiftStreamingMarkdown
import SwiftUI

// MARK: - Message Bubble

public struct MessageBubbleView: View {
    public let message: StreamingMessage
    public let isInline: Bool

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
                ForEach(message.blocks) { block in
                    MessageBlockBubble(block: block)
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

    /// Message-level: every block renders statically (no live stream).
    /// Test-visible (not API) — asserted by CacheEvictionTests.
    internal var usesStaticMarkdown: Bool { message.isStreamFinished }
}

// MARK: - One block

/// Renders one `MessageBlock` by its `kind` + finish/source state — the
/// per-block render derivation in the design spec:
/// `.user` → static blue text; `isStreamFinished` → static `MarkdownView`
/// (finished WINS even when a source is present); live source → streamed;
/// else placeholder.
internal struct MessageBlockBubble: View {
    let block: StreamingMessage.MessageBlock

    @State private var thinkingExpanded = false

    var body: some View {
        switch block.kind {
        case .user:
            userBubble
        case .thinking:
            thinkingBubble
        case .reply:
            replyBubble
        }
    }

    /// Test-visible render decision (not API).
    internal var usesStaticMarkdown: Bool {
        block.kind == .user || block.isStreamFinished
    }

    // MARK: User prompt — instant static blue bubble (never streams)

    private var userBubble: some View {
        Text(block.content ?? "")
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: Thinking — collapsible, streams markdown

    private var thinkingBubble: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    thinkingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                    Text("Show thinking")
                        .font(.caption2)
                    Spacer()
                    // Renders only on re-created controllers: the cached
                    // rootView is frozen, so a live finished message keeps
                    // this block's isStreamFinished false (streamed view shows
                    // the final text instead). On reload / post-eviction
                    // scroll-back the caption appears.
                    if block.isStreamFinished {
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
            .accessibilityIdentifier("thinking-toggle")

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
    }

    @ViewBuilder
    private var thinkingContent: some View {
        if block.isStreamFinished {
            MarkdownView(text: block.content ?? "")
                .transition(.identity)
        } else if let source = block.streamSource {
            StreamedMarkdownView(source: source)
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

    // MARK: Reply — normal markdown bubble, always visible

    private var replyBubble: some View {
        replyContent
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var replyContent: some View {
        if block.isStreamFinished {
            MarkdownView(text: block.content ?? "")
        } else if let source = block.streamSource {
            StreamedMarkdownView(source: source)
        } else {
            // Empty placeholder while waiting for the reply to start.
            Text("")
                .frame(minHeight: 24)
        }
    }
}
