import UIKit

// MARK: - Settle loop (re-measure async content — no reloadData)

// A display link that re-measures the layout every frame while async content
// is still landing (streaming text, MarkdownView's async parse for static
// messages) and stops once the content size is stable. Without it, a cell
// measured before its SwiftUI content finished rendering stays too small and
// the rendered bubble overflows onto its neighbors (the seeded-message overlap).
//
// The link's target is a WEAK proxy, not self: a CADisplayLink strongly
// retains its target, so `self → settleLink → self` would be a retain cycle
// that keeps the controller (and any window-hosted view) alive forever — and
// crashes window-hosted tests at teardown ("Cannot form weak reference to
// instance of class UIWindow ... over-released"). With a weak target the
// controller can deallocate; the proxy then no-ops and the run loop releases
// the link.

@MainActor
private final class SettleLinkTarget {
    weak var controller: ChatCollectionViewController?
    init(_ controller: ChatCollectionViewController) { self.controller = controller }
    @objc nonisolated func tick() {
        MainActor.assumeIsolated { controller?.settleTick() }
    }
}

extension ChatCollectionViewController {

    func scheduleSettle() {
        guard settleLink == nil else { return }
        settleTicks = 0
        stableTicks = 0
        lastContentHeight = -1
        let target = SettleLinkTarget(self)
        let link = CADisplayLink(target: target, selector: #selector(SettleLinkTarget.tick))
        link.add(to: .main, forMode: .common)
        settleLink = link
    }

    func stopSettleLink() {
        settleLink?.invalidate()
        settleLink = nil
    }

    @objc func settleTick() {
        // Re-measure NON-streaming async content (initial load, the static
        // markdown parse on append, the finished message on finish). Streaming
        // growth is handled change-driven by RenderedHeightObserver →
        // onBubbleHeightChanged, so this loop NEVER blind-measures while a
        // stream is active — that is exactly the 60fps poll this design removes.
        let isStreaming = activeStreamingID != nil
        if !isStreaming {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            updateTopInsetForShortContent()
            collectionView.layoutIfNeeded()
            // Non-streaming async growth (a static MarkdownView's parse on
            // initial load / append / finish) has NO observer to trigger the
            // lazy scroll — RenderedHeightObserver only wraps STREAMED content.
            // Re-pin the bottom here so the initial load lands at the bottom
            // and the keyboard push-up (which only fires near the bottom)
            // engages. Skipped while streaming: the lazy scroll owns following.
            if shouldFollow { scrollToBottom(animated: false) }
        }

        let current = collectionView.contentSize.height
        if abs(current - lastContentHeight) < config.settleTolerance {
            stableTicks += 1
        } else {
            stableTicks = 0
            lastContentHeight = current
        }

        settleTicks += 1
        if settleTicks > config.settleMaxTicks, stableTicks >= config.settleStableTicks {
            stopSettleLink()
        }
        evictCachedControllers()
    }
}
