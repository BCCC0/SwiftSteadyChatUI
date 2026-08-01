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
| <video src="https://github.com/user-attachments/assets/97c940d7-0f63-492d-ba91-2304429422c8" controls muted loop width="240"></video> | <video src="https://github.com/user-attachments/assets/585784e8-c0b4-48a7-8912-483bdaa61f01" controls muted loop width="240"></video> | <video src="https://github.com/user-attachments/assets/6fab7299-0e81-4f54-b57e-12a17998e473" controls muted loop width="240"></video> |

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
    .package(url: "https://github.com/BCCC0/SwiftSteadyChatUI", from: "0.2.0")
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
    private let model: MyLLMModel   // streamThinking/streamReply yield text chunks

    func sendMessage(_ text: String) async {
        // 1. Instant user prompt (a single .user block — always finished).
        messages.append(StreamingMessage(blocks: [
            .init(kind: .user, content: text, isStreamFinished: true)
        ]))
        onMessagesChanged?()

        // 2. Reply: thinking + reply blocks, each with its own stream.
        let thinkingSource = ChatStreamSource()
        let replySource = ChatStreamSource()
        let id = UUID()
        messages.append(StreamingMessage(id: id, blocks: [
            .init(kind: .thinking, content: "", streamSource: thinkingSource),
            .init(kind: .reply, content: "", streamSource: replySource),
        ]))
        onMessagesChanged?()

        // 3. Stream thinking, then the reply (full snapshots each yield).
        var thinking = ""
        for chunk in try await model.streamThinking(to: text) {
            thinking += chunk
            thinkingSource.yield(thinking)
        }
        thinkingSource.finish()

        var reply = ""
        for chunk in try await model.streamReply(to: text) {
            reply += chunk
            replySource.yield(reply)
        }
        replySource.finish()

        // 4. Replace with FINISHED blocks (stored ⟹ finished; sources kept
        // alive so a kept cached bubble renders the final text statically).
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx] = StreamingMessage(id: id, blocks: [
            .init(kind: .thinking, content: thinking, streamSource: thinkingSource, isStreamFinished: true),
            .init(kind: .reply, content: reply, streamSource: replySource, isStreamFinished: true),
        ])
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
> 1. `messages` must stay *static mid-stream*. Text flows through each block's
>    `ChatStreamSource` (see `MessageBlock.streamSource`), and the array is only
>    ever *replaced* — never mutated in place — while a message is streaming.
>    This is what lets the collection view avoid reloading.
> 2. A message's blocks (`kind`/`content`/finish) are **final at first render** —
>    the cached bubble captures the struct by value. All evolving text goes
>    through each block's `streamSource`; when a stream ends, **replace** the
>    message with finished copies (keeping `streamSource` alive, as in the
>    example above). Only finished blocks should be persisted (`stored ⟹
>    finished`); `streamSource` is never encoded.

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
- `StreamingMessage` — the display model (`id`, `blocks`, derived `role`).
  `MessageBlock` (`kind`: `.thinking`/`.reply`/`.user`, `content`,
  `streamSource`, `isStreamFinished`) is the unit of streaming; `BlockKind`
  distinguishes the instant user prompt from the reply class.
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
(13 UI tests covering keyboard push-up, streaming flicker, and streamed
thinking). Regenerate it
with `make generate-sample-project`.

## Development

```sh
make help                  # Show all targets
make lint                  # SwiftLint (strict)
make test                  # Package unit tests (49 Swift Testing tests)
make build-sample          # Generate + build the sample app
make ci                    # lint + test + build-sample (same as CI)
```

## License

MIT. See [LICENSE](LICENSE).
