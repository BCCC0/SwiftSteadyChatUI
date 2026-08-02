import UIKit

// MARK: - Scroll

extension ChatCollectionViewController {
    func distanceFromBottom() -> CGFloat {
        let inset = collectionView.adjustedContentInset
        return ScrollMath.distanceFromBottom(
            contentSizeHeight: collectionView.contentSize.height,
            contentOffsetY: collectionView.contentOffset.y,
            boundsHeight: collectionView.bounds.height,
            adjustedBottomInset: inset.bottom
        )
    }

    func isNearBottom() -> Bool {
        ScrollMath.isNearBottom(distance: distanceFromBottom())
    }

    func scrollToBottom(animated: Bool) {
        collectionView.layoutIfNeeded()
        let inset = collectionView.adjustedContentInset
        let targetY = ScrollMath.scrollToBottomTarget(
            contentSizeHeight: collectionView.contentSize.height,
            boundsHeight: collectionView.bounds.height,
            adjustedBottomInset: inset.bottom,
            topInset: inset.top
        )
        collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
    }

    /// Push short content to the bottom by adjusting contentInset.top.
    func updateTopInsetForShortContent() {
        let topInset = ScrollMath.topInsetForShortContent(
            contentSizeHeight: collectionView.contentSize.height,
            boundsHeight: collectionView.bounds.height,
            bottomInset: collectionView.contentInset.bottom
        )
        if collectionView.contentInset.top != topInset {
            collectionView.contentInset.top = topInset
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateFABVisibility()
    }

    /// The follow is broken INSTANTLY on any user drag (before the first scroll
    /// tick), so a gesture is never fought by the auto-scroll. Re-engaging is an
    /// explicit action only (send a prompt, tap the FAB) — never by returning to
    /// the bottom, so there is no geometric threshold anywhere.
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        followState = FollowState.transition(current: followState, event: .gestureBegan)
    }
}
