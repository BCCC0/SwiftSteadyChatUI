import Foundation

extension MessageRecord {
    /// Map a stored record to its display projection. On re-entry the consumer
    /// hydrates its array from these (sources nil → static render).
    func toStreamingMessage() -> StreamingMessage? {
        guard let kind = StreamingMessage.MessageKind(rawValue: kindRaw) else { return nil }
        return StreamingMessage(
            id: id, kind: kind, content: content, thinking: thinking,
            timestamp: timestamp, isStreamFinished: isStreamFinished
        )
    }
}
