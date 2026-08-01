// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftSteadyChatUI",
  defaultLocalization: "en",
  platforms: [.iOS("18.0")],
  products: [
    .library(
      name: "SwiftSteadyChatUI",
      targets: ["SwiftSteadyChatUI"])
  ],
  dependencies: [
    // NOTE: SwiftPM cannot resolve SwiftStreamingMarkdown 0.6.0 by version
    // (`from: "0.6.0"`) because its manifest declares `highlightswift` and
    // `iosMath` by revision, and SwiftPM forbids a version-based dependency
    // from transitively depending on unstable (revision-based) packages.
    // `revision:` pins to the exact v0.6.0 tag commit (c7b12f7) and allows the
    // graph to resolve. Revisit once SwiftStreamingMarkdown tags a version
    // whose manifest uses stable dependencies.
    .package(url: "https://github.com/microsoft/SwiftStreamingMarkdown", revision: "c7b12f7b3d77caa188fd1fc056d0f7ce305ef5cd")
  ],
  targets: [
    .target(
      name: "SwiftSteadyChatUI",
      dependencies: [
        .product(name: "SwiftStreamingMarkdown", package: "SwiftStreamingMarkdown")
      ],
      path: "Sources/SwiftSteadyChatUI"
    ),
    .testTarget(
      name: "SwiftSteadyChatUITests",
      dependencies: ["SwiftSteadyChatUI"],
      path: "Tests/SwiftSteadyChatUITests"
    )
  ]
)
