# Agent Instructions for SwiftSteadyChatUI

> **Trust these instructions first.** Only search the repository if information
> here is incomplete or wrong.

## Project Overview

SwiftSteadyChatUI is a Swift Package that provides a **flicker-free streaming
chat UI layer for iOS** built on SwiftUI and
[SwiftStreamingMarkdown](https://github.com/microsoft/SwiftStreamingMarkdown).
Apps integrate it by conforming a service to the one public seam
(`ChatService`) and embedding `ChatScreen(service:)` in their SwiftUI
hierarchy. The package is iOS-only, distributed via **Swift Package Manager
only**, and ships with a demo app under `Examples/`.

**Key technologies:**

| Topic | Value |
|---|---|
| Language | Swift |
| UI | SwiftUI (wrapper) + UIKit (hosting/collection controller) |
| swift-tools-version | 5.9 |
| Minimum iOS deployment | iOS 18.0 |
| Build system | Swift Package Manager (no CocoaPods, no Bazel) |
| Linter | SwiftLint (config: `.swiftlint.yml`, run via `swiftlint --strict`) |
| Unit tests | Swift Testing (40 tests, `Tests/SwiftSteadyChatUITests/`) |
| UI tests | XCTest (12 tests, hosted by the demo app under `Examples/`) |

## Directory Structure

```
SwiftSteadyChatUI/
├── Makefile                                 # Common local development commands
├── Package.swift                            # SPM manifest — single library target
├── Sources/
│   └── SwiftSteadyChatUI/                   # The library target
│       ├── ChatScreen.swift                 # SwiftUI wrapper (UIViewControllerRepresentable)
│       ├── ChatCollectionViewController.swift  # The hosting chat controller
│       ├── ChatService.swift                # The one public seam protocol
│       ├── ChatStreamSource.swift           # AsyncStream<String> → StreamedMarkdownSource bridge
│       ├── StreamingMessage.swift           # Display model (role, content, streamSource, …)
│       ├── MessageBubbleView.swift          # SwiftUI message bubble
│       ├── ChatInputBar.swift               # UIKit text input bar
│       ├── ScrollToBottomButton.swift       # Floating action button
│       ├── ChatUIConfig.swift               # Behavior/appearance knobs
│       ├── ScrollMath.swift                 # Pure scroll-position math (no UIKit deps)
│       ├── ScrollFollow.swift               # Near-bottom / scroll-follow logic
│       ├── KeyboardHandling.swift           # keyboardLayoutGuide + contentInset keyboard logic
│       ├── SettleLoop.swift                 # Display-link re-measure loop (no reloadData)
│       ├── HostedContentCell.swift          # Cell that hosts a cached SwiftUI view
│       └── BottomInset.swift                # Required bottom inset math
├── Tests/
│   └── SwiftSteadyChatUITests/              # Swift Testing unit tests (ScrollMath, diffing, cache, seam)
├── Examples/
│   └── SwiftSteadyChatUISample/             # Demo app + XCTest UI suite (built from public API only)
├── .github/workflows/ci.yml                 # SwiftLint + SPM unit tests + sample-app build
├── .swiftlint.yml                           # Lint rules
├── .xcode-version                           # Minimum Xcode version
└── CONTRIBUTING.md                          # Contributor guide
```

## Architecture

The core idea is a **cached-hosting-controller** pattern. One
`UIHostingController<MessageBubbleView>` is cached **per message UUID** and
**outlives the cell**. The collection cell merely hosts the cached hosting
view. Because streaming text flows through the message's `ChatStreamSource`
AsyncStream — while the `messages` array stays static mid-stream — the
collection view never reloads mid-stream. `StreamedMarkdownView` keeps its
iterator and re-renders in place, which is what eliminates per-chunk flicker.

- **`ChatService` contract:** `messages` must stay static mid-stream. The
  array is only ever *replaced*, never mutated in place, while a message is
  streaming.
- **Keyboard:** ownership stays in UIKit. The input bar is pinned to
  `keyboardLayoutGuide`; the scroll view uses `contentInset.bottom`. SwiftUI
  keyboard avoidance must not resize the chat container (embed with
  `.ignoresSafeArea(.keyboard)`).
- **Settle loop:** a display link re-measures the layout every frame while
  async content is still landing (streaming text, `MarkdownView`'s async parse
  for static messages) and stops once content size is stable. This lets bubbles
  **grow in place** without `reloadData`.

## Working Principles

Behavioral guidelines for agents (and humans) working in this repo. These bias
toward caution over speed; for trivial tasks, use judgment.

### 1. Think before coding

Don't assume. Don't hide confusion. Surface tradeoffs.

- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.

### 2. Simplicity first

Minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- If you write 200 lines and it could be 50, rewrite it.

### 3. Surgical changes

Touch only what you must. Clean up only your own mess.

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- Remove imports/variables/functions that *your* changes made unused; don't
  remove pre-existing dead code unless asked.

### 4. Goal-driven execution

Define success criteria. Loop until verified.

- "Add validation" → "Write tests for invalid inputs, then make them pass."
- "Fix the bug" → "Write a test that reproduces it, then make it pass."
- "Refactor X" → "Ensure tests pass before and after."

For multi-step tasks, state a brief plan with a verification step per item.

## Coding Standards

### Naming Conventions

Names should be grammatical, concise, and accurate. Avoid abbreviations and
Boolean-naming mistakes (`isFooEnabled`, not `isEnableFoo`).

### Swift Concurrency

- Prefer `async/await` and `Task`. Avoid `DispatchQueue` / `OperationQueue`
  except when bridging legacy callbacks.
- The streaming pipeline runs on a background task and pushes rendered output
  to the main actor at the boundary; do not move that boundary inward without
  measuring.
- `ChatService` and the UI types are `@MainActor`-isolated; keep that
  isolation off non-UI types that don't need it.

### Main Thread and Rendering Performance

- Code must not block the main thread with sleeps, semaphore waits, busy
  polling, etc.
- Do not perform heavy operations inside SwiftUI view bodies — precompute
  upstream of the view.

### Swift Code Organization

- One primary type per source file. Nested helper types belong inside the
  parent type when they are only meaningful in that context.
- Group related extensions in `Type+Feature.swift` files.
- `Sources/` and `Tests/` are the library surface; the demo app under
  `Examples/` must use **only the public API**.

## Testing

- Unit tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) in
  `Tests/SwiftSteadyChatUITests/` (40 tests: ScrollMath, sync diffing, cache
  eviction, service seam, package smoke).
- UI tests are **XCTest** hosted by the demo app under
  `Examples/SwiftSteadyChatUISample/` (12 tests: keyboard push-up + streaming
  flicker). They launch the demo with launch arguments (`--long-reply`,
  `--seed-messages`) to set up deterministic state.

## Build, Test, and Local Setup

### Common commands

```bash
make help                  # Show all Make targets
make lint                  # SwiftLint (strict)
make test                  # Package unit tests (Swift Testing) on the iOS simulator
make generate-sample-project  # Regenerate the demo app Xcode project (xcodegen)
make build-sample          # Generate + build the demo app for the simulator
make clean                 # Remove local build products
```

### Authoritative command (mirrors CI)

```bash
make ci                    # lint + test + build-sample
```
