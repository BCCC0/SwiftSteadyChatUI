import SwiftUI

/// Reports the wrapped content's IDEAL rendered height — fires `onHeightChange`
/// exactly when the (async) render completes and the content GROWS. The
/// `.fixedSize(horizontal: false, vertical: true)` makes the observer read the
/// content's ideal height, not the hosting cell's constrained frame, so there
/// is no feedback loop with the re-measure.
///
/// Uses `.onGeometryChange` (iOS 16+), NOT a GeometryReader + PreferenceKey:
/// in the frozen-rootView cached-hosting pattern the PreferenceKey mechanism
/// fires `onPreferenceChange` only once and never propagates subsequent growth,
/// which silently deadened the change-driven streaming re-measure. The
/// `onGeometryChange` action fires on every resolved height change.
///
/// The action fires ONLY ON GROWTH (`h > lastHeight`): during streaming the
/// wrapped content only ever grows, and the async markdown render ("the diff
/// redraws the tail") can transiently report a smaller ideal height mid-render.
/// Firing on a decrease would re-measure the cell smaller → the last message is
/// pushed up then back down (the streaming jitter). Growth-only keeps the
/// streaming cell monotonic — it never shrinks mid-stream.
///
/// `@MainActor`: the stored `onHeightChange` closure is non-Sendable and the
/// action mutates `@State`; isolating the struct keeps the closure handoff on
/// the main actor under Swift 6 strict concurrency.
@MainActor
internal struct RenderedHeightObserver<Content: View>: View {
    let content: Content
    var onHeightChange: (CGFloat) -> Void

    @State private var lastHeight: CGFloat = -1

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                if h > lastHeight + 0.5 {
                    lastHeight = h
                    onHeightChange(h)
                }
            }
    }
}
