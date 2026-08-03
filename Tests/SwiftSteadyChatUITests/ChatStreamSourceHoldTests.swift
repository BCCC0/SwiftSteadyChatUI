import Testing
@testable import SwiftSteadyChatUI

@Suite("ChatStreamSource hold")
struct ChatStreamSourceHoldTests {

    @Test("a held table is not delivered until it resolves, then flush-on-finish")
    func heldTableNotDeliveredUntilResolved() async {
        let source = ChatStreamSource()
        var received: [String] = []
        let reader = Task {
            for await s in source.text { received.append(s) }
        }

        let table = "| A | B |\n|---|---|\n| 1 | 2 |"
        let resolved = table + "\n\nnext paragraph"
        let safePrefix = table + "\n\n"   // table closed by the blank; tail held

        source.yield(table)
        source.yield(resolved)
        source.finish()
        await reader.value

        #expect(received == [safePrefix, resolved])
    }

    @Test("a setext-ambiguous single line is held until the next line resolves it")
    func setextSingleLineHeldUntilResolved() async {
        let source = ChatStreamSource()
        var received: [String] = []
        let reader = Task {
            for await s in source.text { received.append(s) }
        }

        source.yield("just one line")                 // held (could become setext)
        source.yield("just one line\nsecond line")    // multi-line paragraph → forwarded
        source.finish()
        await reader.value

        #expect(received == ["just one line\nsecond line"])
    }

    @Test("plain paragraphs stream live, not held")
    func paragraphsStreamLive() async {
        let source = ChatStreamSource()
        var received: [String] = []
        let reader = Task {
            for await s in source.text { received.append(s) }
        }

        let para = "two\nlines of prose"
        source.yield(para)
        source.finish()
        await reader.value

        #expect(received == [para])
    }
}
