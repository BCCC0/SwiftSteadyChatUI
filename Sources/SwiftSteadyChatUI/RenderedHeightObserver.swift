import SwiftUI

private struct RenderedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Reports the wrapped content's IDEAL rendered height — fires `onHeightChange`
/// exactly when the (async) render completes and the content grows. The
/// `.fixedSize(horizontal: false, vertical: true)` makes the GeometryReader read
/// the content's ideal height, not the hosting cell's constrained frame, so
/// there is no feedback loop with the re-measure.
///
/// `@MainActor`: the stored `onHeightChange` closure is non-Sendable and
/// `onPreferenceChange` mutates `@State`; isolating the struct keeps the
/// closure handoff on the main actor under Swift 6 strict concurrency.
@MainActor
internal struct RenderedHeightObserver<Content: View>: View {
    let content: Content
    var onHeightChange: (CGFloat) -> Void

    @State private var lastHeight: CGFloat = -1

    var body: some View {
        content
            .background(GeometryReader { geo in
                Color.clear.preference(key: RenderedHeightKey.self, value: geo.size.height)
            })
            .fixedSize(horizontal: false, vertical: true)
            .onPreferenceChange(RenderedHeightKey.self) { h in
                if abs(h - lastHeight) > 0.5 {
                    lastHeight = h
                    onHeightChange(h)
                }
            }
    }
}
