import SwiftStreamingMarkdown
import SwiftUI

// MARK: - Message Bubble

public struct MessageBubbleView: View {
    public let message: StreamingMessage
    public let isInline: Bool
    /// Fade streamed text words in one-by-one (mirrors
    /// `ChatUIConfig.streamingAnimateText`; UI automation disables it via the
    /// sample's `--no-text-animation` launch arg).
    public let animateStreamingText: Bool
    /// Called when an internal state change alters this bubble's intrinsic
    /// height (a thinking card expands/collapses), so the hosting controller can
    /// re-measure the cell. Nil for static bubbles.
    internal let onLayoutChange: (() -> Void)?
    /// Whether the thinking card is expanded. A thinking message renders its
    /// content collapsed by default; the toggle reveals it.
    @State private var thinkingExpanded = false

    public init(
        message: StreamingMessage,
        isInline: Bool = false,
        animateStreamingText: Bool = true,
        onLayoutChange: (() -> Void)? = nil
    ) {
        self.message = message
        self.isInline = isInline
        self.animateStreamingText = animateStreamingText
        self.onLayoutChange = onLayoutChange
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if message.isUser { Spacer(minLength: isInline ? 40 : 60) }
            bubble
                .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
            if !message.isUser { Spacer(minLength: isInline ? 40 : 60) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isInline ? 0 : 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(message.isUser ? "user-msg" : "assistant-msg")
    }

    /// Test-visible render decision (not API) — asserted by CacheEvictionTests.
    internal var usesStaticMarkdown: Bool { message.isStreamFinished }

    @ViewBuilder
    private var bubble: some View {
        switch message.kind {
        case .user: userBubble
        case .thinking: thinkingBubble
        case .reply: replyBubble
        }
    }

    // MARK: User prompt — instant static blue bubble (never streams)

    private var userBubble: some View {
        Text(message.content ?? "")
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: Thinking — collapsible, streams markdown, left-aligned

    private var thinkingBubble: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { thinkingExpanded.toggle() }
                // Expand/collapse changes this bubble's intrinsic height, so the
                // hosting cell must be re-measured.
                onLayoutChange?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile").font(.caption)
                    Text("Show thinking").font(.caption2)
                    Spacer()
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
        if message.isStreamFinished {
            MarkdownView(text: message.content ?? "").transition(.identity)
        } else if let source = message.streamSource {
            ProgressiveRevealMarkdown(source: source, animateText: animateStreamingText)
                .transition(.identity)
        } else {
            HStack {
                Text("Thinking...").font(.caption).foregroundStyle(.secondary)
                Spacer()
                ProgressView().scaleEffect(0.6)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Reply — normal markdown bubble, always visible, left-aligned

    private var replyBubble: some View {
        replyContent
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var replyContent: some View {
        if message.isStreamFinished {
            MarkdownView(text: message.content ?? "")
        } else if let source = message.streamSource {
            ProgressiveRevealMarkdown(source: source, animateText: animateStreamingText)
        } else {
            // Empty placeholder while waiting for the reply to start.
            Text("").frame(minHeight: 24)
        }
    }
}

// MARK: - Live streaming markdown in a fixed-but-expandable window

/// The live-markdown streaming container: the streamed markdown
/// is LOCKED to the last committed render height (`revealedHeight`, monotonic),
/// so each re-render refills a stable space (no cell-resize jitter) and the
/// window grows in discrete steps on render completion, revealing content
/// downward (top-aligned). The inner `RenderedHeightObserver` reads the
/// markdown's NATURAL height (via `.fixedSize(vertical:)`), not the locked
/// frame — no feedback loop with the committed height. Re-render flicker for
/// complex markdown remains (inherent to live markdown); source-side yield
/// coalescing reduces it.
private struct ProgressiveRevealMarkdown: View {
    let source: ChatStreamSource
    /// Fade streamed text words in one-by-one (see `MessageBubbleView`).
    let animateText: Bool

    init(source: ChatStreamSource, animateText: Bool = true) {
        self.source = source
        self.animateText = animateText
    }

    /// The committed window height. Starts small (the first render is a
    /// fraction of the eventual reply) and only ever grows — monotonic, so the
    /// container never shrinks mid-stream (the streaming jitter). The 10pt
    /// start keeps an empty reply a slim full-width bar rather than a hollow box.
    @State private var revealedHeight: CGFloat = 10

    var body: some View {
        RenderedHeightObserver(
            content: StreamedMarkdownView(
                source: source,
                config: MarkdownRenderConfig(shouldAnimateText: animateText)
            )
        ) { h in
            if h > revealedHeight { revealedHeight = h }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: revealedHeight, alignment: .top)
        .clipped()
    }
}
