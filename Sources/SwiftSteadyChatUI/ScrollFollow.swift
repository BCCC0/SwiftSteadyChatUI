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
        let isInteracting = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        followState = FollowState.transition(current: followState, isInteracting: isInteracting, isNearBottom: isNearBottom())
    }

    /// The follow is broken INSTANTLY on any user drag (before the first scroll
    /// tick), so a gesture is never fought by the auto-scroll.
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        followState = .brokenByGesture
    }

    /// Re-engage when a touch ends at the bottom WITHOUT momentum. With momentum
    /// (`willDecelerate`), the deceleration's scroll ticks still report
    /// `isDecelerating`, so wait for `scrollViewDidEndDecelerating` instead.
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        followState = FollowState.transition(current: followState, isInteracting: false, isNearBottom: isNearBottom())
    }

    /// A flick's momentum ended — returning to the bottom re-engages the follow.
    /// Without this the re-engage is dead: the last scroll tick runs mid-gesture
    /// (isInteracting is still true), no trailing `scrollViewDidScroll` fires
    /// once the offset is static, and the settle loop only READS `shouldFollow`
    /// — so a drag/flick that returns to the bottom would leave the follow
    /// permanently broken for the rest of the stream.
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        followState = FollowState.transition(current: followState, isInteracting: false, isNearBottom: isNearBottom())
    }

    /// A programmatic animated scroll (e.g. the FAB) landed — re-evaluate so a
    /// scroll-to-bottom re-anchors the follow deterministically.
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        followState = FollowState.transition(current: followState, isInteracting: false, isNearBottom: isNearBottom())
    }
}
