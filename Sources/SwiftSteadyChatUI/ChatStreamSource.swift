import Foundation
import SwiftStreamingMarkdown

/// Bridges an AsyncStream<String> to StreamedMarkdownSource for StreamedMarkdownView.
///
/// The UI owns the hold: each `yield` supplies the complete accumulated text,
/// but the source forwards only the SAFE prefix (see `MarkdownHoldBuffer`) —
/// flip-prone tails (unclosed tables/fences, setext-ambiguous lines) are held
/// and delivered once they resolve, or when `finish()` flushes them. The
/// renderer therefore only ever re-renders complete, stable snapshots.
public final class ChatStreamSource: StreamedMarkdownSource, @unchecked Sendable {
    public let text: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    /// The full accumulated text from the consumer's latest `yield`.
    private var accumulated = ""
    /// The number of characters of `accumulated` already forwarded.
    private var forwardedCount = 0

    public init() {
        var cont: AsyncStream<String>.Continuation!
        text = AsyncStream { continuation in
            cont = continuation
        }
        self.continuation = cont
    }

    deinit { continuation.finish() }

    /// Feed the complete accumulated markdown so far. Flip-prone tails are held.
    public func yield(_ text: String) {
        accumulated = text
        let safe = MarkdownHoldBuffer.safeForwardCount(of: text)
        if safe > forwardedCount {
            forwardedCount = safe
            continuation.yield(String(text.prefix(safe)))
        }
    }

    /// Flush any held tail, then end the stream.
    public func finish() {
        if forwardedCount < accumulated.count {
            forwardedCount = accumulated.count
            continuation.yield(accumulated)
        }
        continuation.finish()
    }
}
