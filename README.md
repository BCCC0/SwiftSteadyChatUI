# SwiftSteadyChatUI

A streaming chat user interface library for SwiftUI, built on top of
[SwiftStreamingMarkdown](https://github.com/microsoft/SwiftStreamingMarkdown).

- Swift 5.9+
- iOS 18.0+
- Swift Package Manager

## Status

Scaffolding milestone. The package, module, test target, and sample app are in
place; the streaming chat UI implementation is a follow-up task.

## Development

```sh
make resolve                  # Resolve Swift package dependencies
make generate-sample-project  # Generate the sample app Xcode project
make build-sample             # Generate and build the sample app for the simulator
make test                     # Run package unit tests
make clean                    # Remove local build products
```

## Sample app

A minimal Hello World app that imports `SwiftSteadyChatUI` lives in
`Examples/SwiftSteadyChatUISample/`. It is generated with
[xcodegen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.
