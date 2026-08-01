import UIKit

// MARK: - Bottom Inset

extension ChatCollectionViewController {
    func currentRequiredBottomInset() -> CGFloat {
        view.layoutIfNeeded()
        let frame = collectionView.convert(inputBar.frame, from: view)
        return max(0, collectionView.bounds.maxY - frame.minY)
    }

    func updateBottomInset(animated: Bool, preserveBottom: Bool) {
        let changes = {
            let bottomInset = self.currentRequiredBottomInset()
            self.collectionView.contentInset.bottom = bottomInset
            self.collectionView.verticalScrollIndicatorInsets.bottom = bottomInset
            self.updateTopInsetForShortContent()

            let clamped = ScrollMath.clampedContentOffset(
                currentOffsetY: self.collectionView.contentOffset.y,
                contentSizeHeight: self.collectionView.contentSize.height,
                boundsHeight: self.collectionView.bounds.height,
                bottomInset: bottomInset,
                topInset: self.collectionView.contentInset.top
            )
            if self.collectionView.contentOffset.y != clamped {
                self.collectionView.contentOffset.y = clamped
            }

            if preserveBottom { self.scrollToBottom(animated: false) }
        }
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
                animations: changes)
        } else { changes() }
    }
}
