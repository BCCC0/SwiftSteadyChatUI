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
        // 1. Instant user prompt (a single .user message — always finished).
        messages.append(StreamingMessage(
            id: UUID(), kind: .user, content: text, isStreamFinished: true
        ))
        onMessagesChanged?()

        // 2. Thinking + reply are TWO messages, streamed one at a time (at most
        // one message streams, and it is always the last). Each owns its source.
        let thinkingID = UUID()
        let thinkingSource = ChatStreamSource()
        messages.append(StreamingMessage(
            id: thinkingID, kind: .thinking, content: "",
            streamSource: thinkingSource, isStreamFinished: false
        ))
        onMessagesChanged?()

        var thinking = ""
        for chunk in try await model.streamThinking(to: text) {
            thinking += chunk
            thinkingSource.yield(thinking)
        }
        thinkingSource.finish()
        // Replace with the FINISHED message (stored ⟹ finished; the source is
        // kept alive so a kept cached bubble renders the final text statically).
        if let idx = messages.firstIndex(where: { $0.id == thinkingID }) {
            messages[idx] = StreamingMessage(
                id: thinkingID, kind: .thinking, content: thinking,
                streamSource: thinkingSource, isStreamFinished: true
            )
        }
        onMessagesChanged?()

        let replyID = UUID()
        let replySource = ChatStreamSource()
        messages.append(StreamingMessage(
            id: replyID, kind: .reply, content: "",
            streamSource: replySource, isStreamFinished: false
        ))
        onMessagesChanged?()

        var reply = ""
        for chunk in try await model.streamReply(to: text) {
            reply += chunk
            replySource.yield(reply)
        }
        replySource.finish()
        if let idx = messages.firstIndex(where: { $0.id == replyID }) {
            messages[idx] = StreamingMessage(
                id: replyID, kind: .reply, content: reply,
                streamSource: replySource, isStreamFinished: true
            )
        }
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
> 1. `messages` must stay *static mid-stream*. Text flows through each message's
>    `ChatStreamSource`, and the array is only ever *replaced* — never mutated in
>    place — while a message is streaming. This is what lets the collection view
>    avoid reloading.
> 2. A message's `kind`/`content`/finish are **final at first render** — the
>    cached bubble captures the struct by value. All evolving text goes through
>    its `streamSource`; when a stream ends, **replace** the message with a
>    finished copy (keeping `streamSource` alive, as in the example above). Only
>    finished messages should be persisted (`stored ⟹ finished`); `streamSource`
>    is never encoded.
> 3. **At most one message streams at a time, always the last.** A thinking reply
>    is TWO messages — append `.thinking`, stream it, then append `.reply` and
>    stream it.

### Pinned content above the chat

`ChatScreen` is an opaque full-screen chat — the package provides **no
screen-chrome hooks** (banners, headers, toolbars). To pin a strip above the
messages (a status header, a pinned-message banner, an error bar), the consumer
declares its height and renders whatever it likes, stacked above `ChatScreen`:

```swift
VStack(spacing: 0) {
    MyStatusBar(service: service)            // your view; declare the height
        .frame(height: 44)
    ChatScreen(service: service, config: config)
        .ignoresSafeArea(.keyboard, edges: .bottom)
}
```

The band is plain SwiftUI owned by your app. It can read your service's live
state (e.g. `service.messages.last?.isStreaming`) and drive the app through the
same `ChatService` seam. Because `ChatScreen` handles its own keyboard and
scroll math inside its bounds, the band above cannot disturb them. The sample
app demonstrates this with a live status bar (`StatusBarView`).

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

## Single source of truth (SwiftData)

The package ships `ChatMessageStore` — a SwiftData store that is the **durable
source of truth for the chat record**. It persists two public `@Model` types:

- `MessageRecord` — the message history (`conversationId`, `kind`, `content`,
  `thinking`, `timestamp`, `isStreamFinished`, `order`). Only finished display
  state is stored (`stored ⟹ finished`); `streamSource` is never a stored field.
- `ConversationMeta` — one row per conversation holding an **opaque**
  `systemPrompt`. The package never parses, orders, or interprets it; the
  consumer constructs whatever string it wants and reads it back to compose the
  LLM prompt.

The consumer builds the `ModelContainer`, registering the package's public
`@Model` types, hands it to `ChatMessageStore`, writes finished messages when
streams end, and on re-entry loads `messages(for:)` + `systemPrompt(for:)`:

```swift
let container = try ModelContainer(for: MessageRecord.self, ConversationMeta.self)
let store = ChatMessageStore(modelContainer: container)

// Re-entry: restore the conversation.
let history = store.messages(for: conversationId)
let systemPrompt = store.systemPrompt(for: conversationId)

// When a stream ends: persist the finished message.
try store.replace(finishedMessage, conversationId: conversationId)
```

The `ChatService` seam, render path, and screen-chrome pattern are **unchanged**
— the store never drives the live UI, which runs on the consumer's in-memory
`messages` array.

> **Authoritative-source rule.** The package store is the durable chat record
> the UI reads on re-entry. If a consumer also persists messages in its own
> domain store, that store stays authoritative for the domain (prompt
> construction, pins, previews); write both from the same code paths so they
> cannot diverge.

> **Deletion contract (id-keyed).** `ChatMessageStore` exposes id-keyed
> deletion (`delete(id:conversationId:)` for a single message, `deleteAll(for:)`
> for a conversation). The consumer-facing contract — the controller's
> `deleteMessage(id:conversationId:store:)` — is documented under
> "Per-message actions".

## Per-message actions

`ChatScreen.messageActions { controller, message in … }` hands every bubble a
consumer-defined drop list, rendered as the bubble's context menu. The closure
receives `(controller, message)`; each action's handler receives the message's
`id`, so the consumer holds no ids. Actions are
`ChatMessageAction(title:role:handler:)`, where `role` is `.normal` (default) or
`.destructive` (renders red):

```swift
ChatScreen(service: service, config: config)
    // `.messageActions` returns a `ChatScreen`, so it must be chained before
    // View modifiers like `.ignoresSafeArea`.
    .messageActions { controller, _ in
        [
            .init(title: "Delete", role: .destructive, handler: { [weak controller] id in
                service.deleteLocal(id: id)                                     // service reconciles its own array
                controller?.deleteMessage(id: id, conversationId: conversationId, store: store)  // row + SwiftData record
            }),
            .init(title: "Jump", handler: { [weak controller] id in
                controller?.scrollToMessage(id: id, anchor: .center)             // breaks the follow internally
            })
        ]
    }
    .ignoresSafeArea(.keyboard, edges: .bottom)
```

The drop list is captured when each bubble's controller is created (its cached
root view is frozen), so state-dependent actions apply only to newly-created
bubbles — existing bubbles keep the list they were created with. Because that
frozen root view is retained by the controller's cache, action handlers must
not strongly capture the controller — use `[weak controller]` in the handler
(as above) or the controller is retained through teardown.

- `controller.deleteMessage(id:conversationId:store:)` removes a message
  atomically: the id-keyed row (mid-list safe), its cached controller, and the
  SwiftData record. The service reconciles its OWN projection (a `delete(id:)`
  method); the package fires no `onMessagesChanged`. A streaming message has no
  record yet (`stored ⟹ finished`), so a mid-stream delete is UI-only — the
  in-flight send task must not re-persist it.
- `controller.breakAutoscroll()` stops the auto-scroll-to-bottom follow; the
  view stays put until a send or a FAB tap re-engages.
- `controller.scrollToMessage(id:anchor:)` scrolls a message to the `.top`,
  `.center`, or `.bottom` of the viewport (`ScrollAnchor`), breaking the follow
  first so the jump sticks.

## Public API

- `ChatScreen` — SwiftUI wrapper (embed directly in a `View`).
- `ChatCollectionViewController` — the underlying `UICollectionViewController`.
- `ChatService` — the protocol to conform to.
- `StreamingMessage` — the display model (one bubble per message: `id`, `kind`,
  `content`, `streamSource`, `isStreamFinished`; derived `role`/`isStreaming`).
  `MessageKind` (`.user`/`.thinking`/`.reply`) decides the bubble; a thinking
  reply is two messages appended and streamed in sequence.
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
(covering keyboard push-up, streaming flicker, and streamed thinking).
Regenerate it
with `make generate-sample-project`.

## Development

```sh
make help                  # Show all targets
make lint                  # SwiftLint (strict)
make test                  # Package unit tests
make build-sample          # Generate + build the sample app
make ci                    # lint + test + build-sample (same as CI)
```

## License

MIT. See [LICENSE](LICENSE).
