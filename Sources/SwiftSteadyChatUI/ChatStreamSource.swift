import Foundation
import SwiftStreamingMarkdown

/// Bridges an AsyncStream<String> to StreamedMarkdownSource for StreamedMarkdownView.
/// Each yield() passes the complete accumulated text (not a delta).
public final class ChatStreamSource: StreamedMarkdownSource, @unchecked Sendable {
    public let text: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    public init() {
        var cont: AsyncStream<String>.Continuation!
        text = AsyncStream { continuation in
            cont = continuation
        }
        self.continuation = cont
    }

    deinit { continuation.finish() }

    public func yield(_ text: String) { continuation.yield(text) }
    public func finish() { continuation.finish() }
}
