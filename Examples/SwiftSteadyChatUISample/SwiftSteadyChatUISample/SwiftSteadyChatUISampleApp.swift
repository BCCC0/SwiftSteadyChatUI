import SwiftUI
import SwiftSteadyChatUI

@main
struct SwiftSteadyChatUISampleApp: App {
    @State private var service = StubChatService.createWithArgs()

    /// UI automation launches with `--no-text-animation` to exercise the stable
    /// (non-animated) streaming render; the default demo keeps the word fade-in.
    private var config: ChatUIConfig {
        let args = ProcessInfo.processInfo.arguments
        var c = ChatUIConfig()
        if args.contains("--no-text-animation") { c.streamingAnimateText = false }
        return c
    }

    var body: some Scene {
        WindowGroup {
            ChatScreen(service: service, config: config)
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
