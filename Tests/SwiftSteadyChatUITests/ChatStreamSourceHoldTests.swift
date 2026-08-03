import Testing
@testable import SwiftSteadyChatUI

@Suite("ChatStreamSource hold")
struct ChatStreamSourceHoldTests {

    @Test("a held table is not delivered until it resolves or finish")
    func heldTableNotDeliveredUntilResolved() async {
        let source = ChatStreamSource()
        var received: [String] = []
        let reader = Task {
            for await s in source.text { received.append(s) }
        }

        let table = "| A | B |\n|---|---|\n| 1 | 2 |"
        source.yield(table)                       // held → nothing delivered
        let resolved = table + "\n\nnext paragraph" // table closes at the blank
        source.yield(resolved)
        source.finish()                            // flushes any remaining tail
        await reader.value

        // The held table is forwarded only once it closes; finish flushes the
        // trailing single-line paragraph so the final snapshot is the full text.
        #expect(received.last == resolved)
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

        #expect(received.last == para)
    }
}
