import UIKit

// MARK: - Settle loop (re-measure async content — no reloadData)

// A display link that re-measures the layout every frame while async content
// is still landing (streaming text, MarkdownView's async parse for static
// messages) and stops once the content size is stable. Without it, a cell
// measured before its SwiftUI content finished rendering stays too small and
// the rendered bubble overflows onto its neighbors (the seeded-message overlap).

extension ChatCollectionViewController {

    func scheduleSettle() {
        guard settleLink == nil else { return }
        settleTicks = 0
        stableTicks = 0
        lastContentHeight = -1
        let link = CADisplayLink(target: self, selector: #selector(settleTick))
        link.add(to: .main, forMode: .common)
        settleLink = link
    }

    func stopSettleLink() {
        settleLink?.invalidate()
        settleLink = nil
    }

    @objc func settleTick() {
        let isStreaming = activeStreamingID != nil

        // Re-measure so cells grow to their actual (async) content height, and
        // re-apply the short-content top inset (its value changes as cells
        // grow — a stale top inset leaves the offset invalid and the view at
        // the top of the conversation).
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        updateTopInsetForShortContent()
        collectionView.layoutIfNeeded()

        let current = collectionView.contentSize.height
        if abs(current - lastContentHeight) < config.settleTolerance {
            stableTicks += 1
        } else {
            stableTicks = 0
            lastContentHeight = current
        }

        // Follow the bottom while the user hasn't scrolled away (initial load,
        // streaming at bottom) so async growth stays anchored at the latest.
        let shouldFollowBottom = !userScrolled || isNearBottom()
        if shouldFollowBottom { scrollToBottom(animated: false) }

        // Only stop once the offset has actually reached the bottom target and
        // the content size is stable — otherwise a late topInset drop can leave
        // the view stranded at the top after the loop exits.
        let inset = collectionView.adjustedContentInset
        let targetY = ScrollMath.scrollToBottomTarget(
            contentSizeHeight: collectionView.contentSize.height,
            boundsHeight: collectionView.bounds.height,
            adjustedBottomInset: inset.bottom,
            topInset: inset.top
        )
        let atTarget = abs(collectionView.contentOffset.y - targetY) < 1
        settleTicks += 1
        // Stop once content is stable and not streaming. When following the
        // bottom, still require atTarget (don't exit mid-scroll); when the user
        // has scrolled away, atTarget never becomes true (we don't scroll), so
        // stop anyway — otherwise the CADisplayLink spins at 60fps forever on a
        // static screen, re-measuring + evicting with no work to do.
        let stableAndDone = stableTicks >= config.settleStableTicks && !isStreaming
        let canStop = atTarget || !shouldFollowBottom
        if settleTicks > config.settleMaxTicks, stableAndDone, canStop {
            stopSettleLink()
        }
        // Bound the cache every tick: finished messages whose cell has scrolled
        // out of the eviction window release their hosting controller (see
        // evictCachedControllers for the window + no-flicker guards).
        evictCachedControllers()
    }
}
