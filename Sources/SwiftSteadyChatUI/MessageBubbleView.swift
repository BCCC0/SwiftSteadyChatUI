import SwiftStreamingMarkdown
import SwiftUI

// MARK: - Message Bubble

public struct MessageBubbleView: View {
    public let message: StreamingMessage
    public let isInline: Bool
    /// Called when an internal state change alters this bubble's intrinsic
    /// height (a thinking block expands/collapses), so the hosting controller
    /// can re-measure the cell. Nil for static bubbles.
    internal let onLayoutChange: (() -> Void)?

    public init(
        message: StreamingMessage,
        isInline: Bool = false,
        onLayoutChange: (() -> Void)? = nil
    ) {
        self.message = message
        self.isInline = isInline
        self.onLayoutChange = onLayoutChange
    }

    public var body: some View {
        // Top-aligned: the bubble grows DOWNWARD from its top. Bottom-alignment
        // made a too-short cell push the streaming content UP over the previous
        // message (the streaming overlay).
        HStack(alignment: .top, spacing: 6) {
            if message.role == .user {
                Spacer(minLength: isInline ? 40 : 60)
            }

            // Deliberate design (2026-08-05): the bubble column fills the
            // available width, so assistant bubbles (including an EMPTY streaming
            // block, a slim bar with no intrinsic width) span the full bubble
            // width. Trailing alignment pins compact blocks (user prompts, the
            // thinking header) to the trailing edge.
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(message.blocks) { block in
                    MessageBlockBubble(block: block, onLayoutChange: onLayoutChange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

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
    /// Notifies the hosting controller to re-measure after an expand/collapse
    /// changes this bubble's intrinsic height.
    let onLayoutChange: (() -> Void)?

    @State private var thinkingExpanded = false

    init(
        block: StreamingMessage.MessageBlock,
        onLayoutChange: (() -> Void)? = nil
    ) {
        self.block = block
        self.onLayoutChange = onLayoutChange
    }

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
                // The expand/collapse changes this bubble's intrinsic height,
                // so the hosting cell must be re-measured (nothing else will
                // trigger it once the settle loop has stopped).
                onLayoutChange?()
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
            ProgressiveRevealMarkdown(source: source)
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
            ProgressiveRevealMarkdown(source: source)
        } else {
            // Empty placeholder while waiting for the reply to start.
            Text("")
                .frame(minHeight: 24)
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

    /// The committed window height. Starts small (the first render is a
    /// fraction of the eventual reply) and only ever grows — monotonic, so the
    /// container never shrinks mid-stream (the streaming jitter). The 10pt
    /// start keeps an empty reply a slim full-width bar rather than a hollow box.
    @State private var revealedHeight: CGFloat = 10

    var body: some View {
        RenderedHeightObserver(
            content: StreamedMarkdownView(
                source: source,
                config: MarkdownRenderConfig(shouldAnimateText: true)
            )
        ) { h in
            if h > revealedHeight { revealedHeight = h }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: revealedHeight, alignment: .top)
        .clipped()
    }
}
