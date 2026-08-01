import SwiftUI
import SwiftSteadyChatUI

@main
struct SwiftSteadyChatUISampleApp: App {
    @State private var service = StubChatService.createWithArgs()

    var body: some Scene {
        WindowGroup {
            ChatScreen(service: service)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .task {
                    // Demo helper (`--auto-thinking`): auto-send a prompt shortly
                    // after launch so the thinking block streams on its own.
                    guard let prompt = service.autoSendText else { return }
                    try? await Task.sleep(for: .milliseconds(900))
                    await service.sendMessage(prompt)
                }
        }
    }
}
