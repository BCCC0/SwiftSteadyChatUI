import SwiftUI
import SwiftSteadyChatUI

@main
struct SwiftSteadyChatUISampleApp: App {
    @State private var service = StubChatService.createWithArgs()

    /// Built from launch args: `--mode streamingMarkdown|antiFlicker` selects
    /// the streaming render mode for the whole chat.
    private var config: ChatUIConfig {
        let args = ProcessInfo.processInfo.arguments
        let mode: ChatUIConfig.StreamingMode
        if let idx = args.firstIndex(of: "--mode") {
            switch args.dropFirst(idx + 1).first {
            case "streamingMarkdown": mode = .streamingMarkdown
            case "unlocked": mode = .streamingMarkdownUnlocked
            default: mode = .antiFlicker
            }
        } else {
            mode = .antiFlicker
        }
        return ChatUIConfig(streamingMode: mode)
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
