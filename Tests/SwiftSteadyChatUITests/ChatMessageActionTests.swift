import Foundation
import Testing
@testable import SwiftSteadyChatUI

@Suite("Message action types")
struct ChatMessageActionTests {

    @Test("ChatMessageAction defaults to .normal role and carries the handler")
    func actionDefaults() {
        let id = UUID()
        var handled: UUID?
        let action = ChatMessageAction(title: "Copy") { handled = $0 }
        #expect(action.title == "Copy")
        #expect(action.role == .normal)
        action.handler(id)
        #expect(handled == id)
    }

    @Test("a destructive role is preserved")
    func destructiveRole() {
        let action = ChatMessageAction(title: "Delete", role: .destructive) { _ in }
        #expect(action.role == .destructive)
    }

    @Test("ScrollAnchor has all three cases")
    func scrollAnchors() {
        #expect([ScrollAnchor.top, .center, .bottom].count == 3)
    }
}
