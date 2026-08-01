# SwiftSteadyChatUI

A **flicker-free streaming-markdown chat UI layer for iOS**, built on
[SwiftUI](https://developer.apple.com/xcode/swiftui/) and
[SwiftStreamingMarkdown](https://github.com/microsoft/SwiftStreamingMarkdown).

`SwiftSteadyChatUI` gives you a drop-in, one-seam chat screen whose bubbles
render markdown **as it streams in** from your LLM service — without the
per-chunk flicker, keyboard jump, and layout thrash that plague naive
streaming chat implementations.

- Swift 5.9+
- iOS 18.0+
- Swift Package Manager

Built with this library: **[SwiftTavern](https://github.com/BCCC0/SwiftTavern)** — a native iOS LLM role-playing chat app.

## Demo

Flicker-free streaming, correct keyboard handling, and grows-in-place — in action:

| Streaming long markdown reply | Keyboard push-up & dismiss | Scrolled away: no push-up |
|---|---|---|
| <video src="https://github.com/BCCC0/SwiftSteadyChatUI/raw/main/demo/demo1.mp4" controls muted loop width="240"></video> | <video src="https://github.com/BCCC0/SwiftSteadyChatUI/raw/main/demo/demo2.mp4" controls muted loop width="240"></video> | <video src="https://github.com/BCCC0/SwiftSteadyChatUI/raw/main/demo/demo3.mp4" controls muted loop width="240"></video> |

Recorded on the iPhone 17 simulator with `make record-demo`. The three demo
clips are driven by recording-only UI tests (see
`Examples/SwiftSteadyChatUISample/SwiftSteadyChatUISampleDemoUITests/`).

## The three guarantees

1. **No flicker.** Every message owns a cached hosting controller that lives
   *outside* the collection view and outlives its cell. Streaming text flows
   through that controller's `StreamedMarkdownView`, so the collection view is
   never reloaded mid-stream and bubbles never flash or blank between chunks.
2. **Correct keyboard.** Keyboard ownership stays in UIKit: the input bar is
   pinned to the keyboard layout guide and the scroll view uses
   `contentInset.bottom`, so the chat container's frame is never resized by
   SwiftUI keyboard avoidance. The scroll position (and the near-bottom math
   that drives the scroll-to-bottom button) stays accurate while the keyboard
   animates.
3. **Grows in place.** Bubbles grow taller as markdown lands. A settle loop
   re-measures asynchronous content (streaming text, async markdown parsing)
   without calling `reloadData`, and the view follows the bottom when you are
   near it — no jitter, no overlap.

## Installation

Add the package to your app via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/BCCC0/SwiftSteadyChatUI", from: "0.1.0")
]
```

Then add `SwiftSteadyChatUI` to your target's dependencies.

## Usage

The whole API is **one seam**: conform your chat service to `ChatService` and
hand it to `ChatScreen`. Everything else — streaming markdown bubbles, the
input bar, keyboard handling, scroll following, the scroll-to-bottom button —
is provided.

```swift
import SwiftSteadyChatUI
import SwiftUI

// 1. Conform your chat service (an @Observable model works great).
@MainActor
final class MyChatService: ChatService {
    var messages: [StreamingMessage] = []
    var onMessagesChanged: (() -> Void)?
    private let model: MyLLMModel   // your LLM client — streamReply yields text chunks

    func sendMessage(_ text: String) async {
        messages.append(StreamingMessage(role: .user, content: text))
        onMessagesChanged?()

        let source = ChatStreamSource()
        let id = UUID()
        messages.append(StreamingMessage(id: id, role: .assistant, content: "", streamSource: source))
        onMessagesChanged?()

        var accumulated = ""
        for chunk in try await model.streamReply(to: text) {
            accumulated += chunk
            source.yield(accumulated)   // each yield passes the full accumulated text
        }
        source.finish()

        // IMPORTANT: replace the streaming message with a FINISHED copy that
        // keeps `streamSource` alive. The UI's cached bubble renders the final
        // text statically once `isStreamFinished == true` — without this the
        // settle loop never stops and the cache never evicts.
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx] = StreamingMessage(
            id: id, role: .assistant, content: accumulated,
            streamSource: source, isStreamFinished: true
        )
        onMessagesChanged?()
    }
}

// 2. Embed the chat screen in your SwiftUI hierarchy.
struct ChatView: View {
    @State private var service = MyChatService()

    var body: some View {
        ChatScreen(service: service, config: .init())
            .ignoresSafeArea(.keyboard)   // the UI layer owns the keyboard
    }
}
```

> **`ChatService` contract:**
> 1. `messages` must stay *static mid-stream*. Text flows through each streaming
>    message's `ChatStreamSource` (see `StreamingMessage.streamSource`), and the
>    array is only ever *replaced* — never mutated in place — while a message is
>    streaming. This is what lets the collection view avoid reloading.
> 2. A message's `content`/`thinking`/`role` must be **final at first render** —
>    the cached bubble captures the struct by value. All evolving text goes
>    through `streamSource`; when the stream ends, **replace** the message with a
>    finished copy (keeping `streamSource` alive, as in the example above). A
>    service that clears `streamSource` on finish will show a stale/empty bubble
>    until eviction re-creates it.

### Configuration

`ChatUIConfig` exposes the knobs that matter:

| Property | Default | Purpose |
|---|---|---|
| `dismissKeyboardOnSend` | `true` | Dismiss the keyboard when the user sends a message |
| `showsScrollToBottomButton` | `true` | Show the scroll-to-bottom FAB |
| `messageSpacing` | `8` | Vertical spacing between bubbles (points) |
| `settleMaxTicks` / `settleStableTicks` / `settleTolerance` | `24` / `5` / `0.5` | Settle-loop tolerances for re-measuring async content |

The defaults match the validated reference layout the UI tests were verified
against — change them deliberately.

## Public API

- `ChatScreen` — SwiftUI wrapper (embed directly in a `View`).
- `ChatCollectionViewController` — the underlying `UICollectionViewController`.
- `ChatService` — the protocol to conform to.
- `StreamingMessage` — the display model (`role`, `content`, `thinking`,
  `streamSource`, `isStreamFinished`).
- `ChatStreamSource` — bridges an `AsyncStream<String>` to
  `StreamedMarkdownSource`.
- `ChatUIConfig` — behavior/appearance configuration.
- `MessageBubbleView` — the message bubble view (composable on its own).
- `ScrollMath` — pure scroll-position math (no UIKit dependencies).

## Demo app

The sample app in `Examples/SwiftSteadyChatUISample/` is **built entirely from
the public API** — it imports only `SwiftSteadyChatUI` and exercises the same
`ChatService` seam, `ChatScreen` embedding, and `ChatUIConfig` you would use in
your own app. It doubles as the host for the UI-test suite
(12 UI tests covering keyboard push-up and streaming flicker). Regenerate it
with `make generate-sample-project`.

## Development

```sh
make help                  # Show all targets
make lint                  # SwiftLint (strict)
make test                  # Package unit tests (41 Swift Testing tests)
make build-sample          # Generate + build the sample app
make ci                    # lint + test + build-sample (same as CI)
```

## License

MIT. See [LICENSE](LICENSE).
