import Testing
@testable import SwiftSteadyChatUI

@Test("Version constant is set")
func versionConstantIsSet() {
  #expect(!SwiftSteadyChatUI.version.isEmpty)
  #expect(SwiftSteadyChatUI.version == "0.1.0")
}
