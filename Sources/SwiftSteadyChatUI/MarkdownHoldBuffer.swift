import Foundation

/// Decides how much of a streamed markdown snapshot to forward to the renderer
/// now versus hold back. Pure and testable (no UIKit/SwiftUI).
///
/// Streams everything live EXCEPT a trailing flip-prone region: an unclosed
/// code fence, a pending/active table, or a single-line paragraph that could
/// still become a setext heading. The held tail is forwarded once it resolves
/// (or on `finish()`).
enum MarkdownHoldBuffer {

    /// The number of leading characters of `text` safe to forward now.
    /// `text[count...]` is held until it resolves or the stream finishes.
    static func safeForwardCount(of text: String) -> Int {
        var lines: [(offset: Int, text: Substring)] = []
        var cursor = text.startIndex
        var offset = 0
        while cursor < text.endIndex {
            if let nl = text[cursor...].firstIndex(of: "\n") {
                lines.append((offset, text[cursor..<nl]))
                offset += text[cursor..<nl].count + 1   // line + newline
                cursor = text.index(after: nl)
            } else {
                lines.append((offset, text[cursor...]))
                break
            }
        }

        var inFence = false
        var holdStart: Int?          // char offset of an unclosed fence opener
        var pendingTableStart: Int?  // trailing | lines (table candidate)
        var activeTableStart: Int?   // a confirmed table (delimiter seen)
        var paragraphCount = 0       // trailing paragraph lines
        var paragraphStart: Int?

        for line in lines {
            let offset = line.offset
            let t = String(line.text)
            let trimmed = t.trimmingCharacters(in: .whitespaces)

            if inFence {
                if isFence(trimmed) {
                    inFence = false
                    holdStart = nil
                }
                pendingTableStart = nil
                activeTableStart = nil
                paragraphCount = 0
                paragraphStart = nil
            } else if isFence(trimmed) {
                inFence = true
                holdStart = offset
                pendingTableStart = nil
                activeTableStart = nil
                paragraphCount = 0
                paragraphStart = nil
            } else if trimmed.isEmpty {
                pendingTableStart = nil
                activeTableStart = nil
                paragraphCount = 0
                paragraphStart = nil
            } else if isDelimiter(t) {
                activeTableStart = pendingTableStart ?? offset
                pendingTableStart = nil
                paragraphCount = 0
                paragraphStart = nil
            } else if isPipeRow(trimmed) {
                if activeTableStart == nil && pendingTableStart == nil {
                    pendingTableStart = offset
                }
                paragraphCount = 0
                paragraphStart = nil
            } else {
                pendingTableStart = nil
                if isSetextUnderline(trimmed) || isBlockStart(trimmed) {
                    paragraphCount = 0
                    paragraphStart = nil
                } else {
                    paragraphCount += 1
                    if paragraphCount == 1 { paragraphStart = offset }
                }
            }
        }

        var hold: Int?
        if let s = holdStart { hold = max(hold ?? 0, s) }
        if let s = activeTableStart { hold = max(hold ?? 0, s) }
        if let s = pendingTableStart { hold = max(hold ?? 0, s) }
        if paragraphCount == 1, let s = paragraphStart { hold = max(hold ?? 0, s) }
        return hold ?? text.count
    }

    // MARK: Line predicates

    /// A fenced-code marker: 3+ of the same backtick or tilde, optionally
    /// followed by an info string (e.g. "```swift"). A backtick fence's info
    /// string may not contain backticks (CommonMark); tilde fences accept any.
    private static func isFence(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, first == "`" || first == "~" else { return false }
        let marker = trimmed.prefix(while: { $0 == first })
        guard marker.count >= 3 else { return false }
        if first == "`" {
            return !trimmed.dropFirst(marker.count).contains("`")
        }
        return true
    }

    /// A line that starts with `|`.
    private static func isPipeRow(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("|")
    }

    /// A table delimiter row: `|`-wrapped, remaining chars are only `-`/`:`.
    private static func isDelimiter(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|") else { return false }
        let stripped = t.filter { $0 != "|" && $0 != " " }
        return !stripped.isEmpty && stripped.allSatisfy { $0 == "-" || $0 == ":" }
    }

    /// A setext underline: 3+ of the same `-` or `=`.
    private static func isSetextUnderline(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3, let first = trimmed.first,
              first == "-" || first == "=" else { return false }
        return trimmed.allSatisfy { $0 == first }
    }

    /// A line that starts a block (ATX heading, blockquote, list item,
    /// thematic break) — never a paragraph/setext candidate.
    private static func isBlockStart(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("#") { return true }
        if trimmed.hasPrefix(">") { return true }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") { return true }
        if let d = trimmed.first, d.isNumber {
            let rest = trimmed.drop(while: { $0.isNumber })
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") { return true }
        }
        return isThematicBreak(trimmed)
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3, let first = trimmed.first,
              first == "-" || first == "*" || first == "_" else { return false }
        return trimmed.allSatisfy { $0 == first }
    }
}
