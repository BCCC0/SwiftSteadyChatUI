import SwiftUI
import SwiftSteadyChatUI

@main
struct SwiftSteadyChatUISampleApp: App {
    var body: some Scene {
        WindowGroup {
            ChatScreen(service: StubChatService.createWithArgs())
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }
}
