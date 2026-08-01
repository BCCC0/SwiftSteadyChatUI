import Foundation

/// Pure scroll-position math for a chat collection view.
/// No UIKit dependencies — callers pass raw CGFloat values.
public struct ScrollMath {

    /// How close to the bottom the user must be to count as "near bottom."
    public static let nearBottomThreshold: CGFloat = 100

    // MARK: - Distance

    /// Positive = user is above the bottom. Negative = overscrolled past bottom.
    public static func distanceFromBottom(
        contentSizeHeight: CGFloat,
        contentOffsetY: CGFloat,
        boundsHeight: CGFloat,
        adjustedBottomInset: CGFloat
    ) -> CGFloat {
        let maxY = contentSizeHeight - boundsHeight + adjustedBottomInset
        return maxY - contentOffsetY
    }

    /// True when the user is within the threshold of the bottom.
    public static func isNearBottom(distance: CGFloat) -> Bool {
        distance <= nearBottomThreshold
    }

    // MARK: - Scroll Target

    /// The target `contentOffset.y` to scroll to the visual bottom.
    /// Handles short content via negative offsets (top inset fills the gap).
    public static func scrollToBottomTarget(
        contentSizeHeight: CGFloat,
        boundsHeight: CGFloat,
        adjustedBottomInset: CGFloat,
        topInset: CGFloat
    ) -> CGFloat {
        let maxY = contentSizeHeight - boundsHeight + adjustedBottomInset
        return max(-topInset, maxY)
    }

    // MARK: - Short Content

    /// The extra `contentInset.top` needed to push short content
    /// to the bottom of the visible area so it doesn't float at the top.
    public static func topInsetForShortContent(
        contentSizeHeight: CGFloat,
        boundsHeight: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        let visibleHeight = boundsHeight - bottomInset
        return contentSizeHeight < visibleHeight ? visibleHeight - contentSizeHeight : 0
    }

    // MARK: - Overscroll Clamp

    /// Clamps `contentOffset.y` so it never exceeds the valid scroll range
    /// after an inset change. Prevents the user from landing in overscroll
    /// territory when `contentInset.bottom` shrinks (keyboard dismiss).
    public static func clampedContentOffset(
        currentOffsetY: CGFloat,
        contentSizeHeight: CGFloat,
        boundsHeight: CGFloat,
        bottomInset: CGFloat,
        topInset: CGFloat
    ) -> CGFloat {
        let maxOffsetY = contentSizeHeight - boundsHeight + bottomInset
        if currentOffsetY > maxOffsetY {
            return max(-topInset, maxOffsetY)
        }
        return currentOffsetY
    }
}
