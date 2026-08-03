import SwiftStreamingMarkdown
import SwiftUI

// MARK: - Message Bubble

public struct MessageBubbleView: View {
    public let message: StreamingMessage
    public let isInline: Bool
    /// How this message's streaming blocks render while text arrives.
    public let streamingMode: ChatUIConfig.StreamingMode
    /// Called when an internal state change alters this bubble's intrinsic
    /// height (a thinking block expands/collapses), so the hosting controller
    /// can re-measure the cell. Nil for static bubbles.
    internal let onLayoutChange: (() -> Void)?

    public init(
        message: StreamingMessage,
        isInline: Bool = false,
        streamingMode: ChatUIConfig.StreamingMode = .antiFlicker,
        onLayoutChange: (() -> Void)? = nil
    ) {
        self.message = message
        self.isInline = isInline
        self.streamingMode = streamingMode
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

            VStack(alignment: .trailing, spacing: 4) {
                ForEach(message.blocks) { block in
                    MessageBlockBubble(block: block, streamingMode: streamingMode, onLayoutChange: onLayoutChange)
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
    /// How this block's streaming content renders while text arrives.
    let streamingMode: ChatUIConfig.StreamingMode
    /// Notifies the hosting controller to re-measure after an expand/collapse
    /// changes this bubble's intrinsic height.
    let onLayoutChange: (() -> Void)?

    @State private var thinkingExpanded = false

    init(
        block: StreamingMessage.MessageBlock,
        streamingMode: ChatUIConfig.StreamingMode = .antiFlicker,
        onLayoutChange: (() -> Void)? = nil
    ) {
        self.block = block
        self.streamingMode = streamingMode
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
            streamedContent(source)
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

    // MARK: Streaming content (mode-selected)

    /// The streaming render for a live block, chosen by `streamingMode`.
    @ViewBuilder
    private func streamedContent(_ source: ChatStreamSource) -> some View {
        switch streamingMode {
        case .antiFlicker:
            PlainThenMarkdown(source: source)
        case .streamingMarkdown:
            ProgressiveRevealMarkdown(source: source)
        case .streamingMarkdownUnlocked:
            StreamedMarkdownView(source: source)
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
            streamedContent(source)
        } else {
            // Empty placeholder while waiting for the reply to start.
            Text("")
                .frame(minHeight: 24)
        }
    }
}

// MARK: - Plain text while streaming, fade into markdown on finish

/// The chosen approach (forensics Option A, refined): while the reply streams,
/// render the accumulated text as PLAIN `Text` — it appends lines with no
/// markdown re-parse and no reflow, so it cannot flicker. On finish, crossfade
/// into the fully-rendered `MarkdownView`. Live formatting appears when the
/// reply settles ("raw while streaming, formatted when settled" — standard chat
/// UX), and the stream is flicker-free by construction.
///
/// Consumes the source directly (like `StreamedMarkdownView` would), so it
/// works in the frozen cached rootView: `isFinished` is driven by the source's
/// stream ENDING, not by the block's `isStreamFinished` flag.
private struct PlainThenMarkdown: View {
    let source: ChatStreamSource

    @State private var accumulated = ""
    @State private var isFinished = false
    /// True once the finish `MarkdownView` has parsed and rendered. The plain
    /// text stays visible until then (never a blank flash); only once ready do
    /// we crossfade into the rendered markdown.
    @State private var markdownReady = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Plain text while streaming — and stays until the markdown is ready.
            if !isFinished || !markdownReady {
                Text(accumulated)
                    .frame(minHeight: 24, alignment: .topLeading)
                    .textSelection(.enabled)
                    .transition(.opacity)
            }
            // The finish markdown: the SAME instance across readiness — it
            // parses once while hidden (zero-height), then fades in + grows on
            // ready. Keeping one instance avoids a second async parse at reveal.
            if isFinished {
                RenderedHeightObserver(content: MarkdownView(text: accumulated)) { h in
                    if h > 0 { markdownReady = true }
                }
                .frame(height: markdownReady ? nil : 0)
                .clipped()
                .opacity(markdownReady ? 1 : 0)
                .transition(.opacity)
            }
        }
        // Constrain to full available width (top-leading). The plain `Text`
        // would otherwise size to its widest line and GROW as text streams,
        // while the finish `MarkdownView` fills width — a width flicker. Fixing
        // the streaming width to the same full width keeps the container stable.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.4), value: markdownReady)
        .task {
            for await text in source.text {
                accumulated = text
            }
            isFinished = true
        }
    }
}

// MARK: - Live streaming markdown in a fixed-but-expandable window

/// The live-markdown streaming container (normal mode): the streamed markdown
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
    /// container never shrinks mid-stream (the streaming jitter).
    @State private var revealedHeight: CGFloat = 40

    var body: some View {
        RenderedHeightObserver(
            content: StreamedMarkdownView(source: source)
        ) { h in
            if h > revealedHeight { revealedHeight = h }
        }
        .frame(height: revealedHeight, alignment: .top)
        .clipped()
    }
}
