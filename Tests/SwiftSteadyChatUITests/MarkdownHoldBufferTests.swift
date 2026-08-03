import Testing
@testable import SwiftSteadyChatUI

@Suite("MarkdownHoldBuffer")
struct MarkdownHoldBufferTests {

    @Test("forwards a multi-line paragraph live")
    func multiLineParagraphStreamsLive() {
        let text = "line one\nline two"
        #expect(MarkdownHoldBuffer.safeForwardCount(of: text) == text.count)
    }

    @Test("holds a single-line paragraph (setext-ambiguous)")
    func singleLineParagraphHeld() {
        let text = "just one line"
        #expect(MarkdownHoldBuffer.safeForwardCount(of: text) == 0)
    }

    @Test("forwards a setext heading once the underline lands")
    func setextHeadingForwards() {
        let text = "heading text\n---"
        #expect(MarkdownHoldBuffer.safeForwardCount(of: text) == text.count)
    }

    @Test("a blank line confirms a paragraph (resets setext hold)")
    func blankLineResetsSetext() {
        let text = "just one line\n\n"
        #expect(MarkdownHoldBuffer.safeForwardCount(of: text) == text.count)
    }

    @Test("forwards an ATX heading (never setext-ambiguous)")
    func headingNotHeld() {
        let text = "# heading"
        #expect(MarkdownHoldBuffer.safeForwardCount(of: text) == text.count)
    }

    @Test("holds an unclosed code fence")
    func unclosedFenceHeld() {
        let text = "before\n```swift\ncode\n"
        let expected = "before\n".count
        #expect(MarkdownHoldBuffer.safeForwardCount(of: text) == expected)
    }

    @Test("forwards a closed code fence")
    func closedFenceForwards() {
        let text = "before\n```swift\ncode\n```\n"
        #expect(MarkdownHoldBuffer.safeForwardCount(of: text) == text.count)
    }

    @Test("holds a table until it closes")
    func unclosedTableHeld() {
        let text = "| A | B |\n|---|---|\n| 1 | 2 |"
        #expect(MarkdownHoldBuffer.safeForwardCount(of: text) == 0)
    }

    @Test("forwards a table once closed by a blank line")
    func closedTableForwards() {
        let text = "| A | B |\n|---|---|\n| 1 | 2 |\n\nnext"
        let expected = "| A | B |\n|---|---|\n| 1 | 2 |\n\n".count
        #expect(MarkdownHoldBuffer.safeForwardCount(of: text) == expected)
    }

    @Test("holds a pending pipe line (table candidate)")
    func pendingPipeHeld() {
        let text = "| A | B |"
        #expect(MarkdownHoldBuffer.safeForwardCount(of: text) == 0)
    }

    @Test("a pipe line followed by paragraph text is a paragraph, not a table")
    func pipeThenParagraphIsNotTable() {
        let text = "| A | B |\nsome words here"
        let expected = "| A | B |\n".count
        // the pipe line is confirmed a paragraph and forwarded; the trailing
        // single paragraph line is held (setext-ambiguous)
        #expect(MarkdownHoldBuffer.safeForwardCount(of: text) == expected)
    }

    @Test("a partial delimiter row confirms the table (no header leak)")
    func partialDelimiterConfirmsTable() {
        let text = "| A | B |\n|-"
        #expect(MarkdownHoldBuffer.safeForwardCount(of: text) == 0)
    }
}
