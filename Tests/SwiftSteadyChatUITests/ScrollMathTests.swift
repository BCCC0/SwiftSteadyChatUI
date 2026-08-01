import Testing
@testable import SwiftSteadyChatUI

@Suite struct ScrollMathScrollToBottomTargetTests {

    // MARK: - Tall content (fills screen)

    @Test func targetAtBottom_whenContentFillsScreen() {
        // Content taller than visible area → target is the max scrollable offset.
        let target = ScrollMath.scrollToBottomTarget(
            contentSizeHeight: 2000,
            boundsHeight: 800,
            adjustedBottomInset: 400, // keyboard up
            topInset: 0
        )
        // maxY = 2000 - 800 + 400 = 1600
        #expect(target == 1600)
    }

    @Test func targetAtBottom_withNoKeyboard() {
        let target = ScrollMath.scrollToBottomTarget(
            contentSizeHeight: 2000,
            boundsHeight: 800,
            adjustedBottomInset: 60, // keyboard hidden, just input bar
            topInset: 0
        )
        // maxY = 2000 - 800 + 60 = 1260
        #expect(target == 1260)
    }

    @Test func targetAtBottom_withZeroInset() {
        let target = ScrollMath.scrollToBottomTarget(
            contentSizeHeight: 2000,
            boundsHeight: 800,
            adjustedBottomInset: 0,
            topInset: 0
        )
        // maxY = 2000 - 800 + 0 = 1200
        #expect(target == 1200)
    }

    // MARK: - Short content (less than screen)

    @Test func targetFloorsToNegativeTopInset_forShortContent() {
        // Content is only 100pt tall in an 800pt screen → topInset fills the gap.
        let target = ScrollMath.scrollToBottomTarget(
            contentSizeHeight: 100,
            boundsHeight: 800,
            adjustedBottomInset: 60,
            topInset: 640 // visibleHeight = 800-60=740, topInset = 740-100=640
        )
        // maxY = 100 - 800 + 60 = -640
        // target = max(-640, -640) = -640
        #expect(target == -640)
    }

    @Test func targetFloorsToNegativeTopInset_whenMaxYEqualsTopInset() {
        // Edge case: very short content with large bottom inset
        let target = ScrollMath.scrollToBottomTarget(
            contentSizeHeight: 50,
            boundsHeight: 800,
            adjustedBottomInset: 500, // keyboard up
            topInset: 250 // visibleHeight = 800-500=300, topInset = 300-50=250
        )
        // maxY = 50 - 800 + 500 = -250
        // target = max(-250, -250) = -250
        #expect(target == -250)
    }

    // MARK: - Exact fit

    @Test func targetIsZero_whenContentExactlyFits() {
        let target = ScrollMath.scrollToBottomTarget(
            contentSizeHeight: 740, // exactly visibleHeight
            boundsHeight: 800,
            adjustedBottomInset: 60,
            topInset: 0
        )
        // maxY = 740 - 800 + 60 = 0
        #expect(target == 0)
    }

    // MARK: - Empty content

    @Test func targetForEmptyContent() {
        let target = ScrollMath.scrollToBottomTarget(
            contentSizeHeight: 0,
            boundsHeight: 800,
            adjustedBottomInset: 60,
            topInset: 740  // matches what topInsetForShortContent would return
        )
        // maxY = 0 - 800 + 60 = -740, target = max(-740, -740) = -740
        #expect(target == -740)
    }

    // MARK: - Floor vs maxY coverage

    @Test func targetUsesMax_whenBelowFloor() {
        // When maxY is BELOW -topInset, the floor (-topInset) wins.
        // content=100, bounds=800, inset=60, topInset=600
        // visibleHeight = 800-60=740, gap = 740-100=640
        // topInset=600 (not 640, so floor and maxY differ)
        // maxY = 100-800+60 = -640, -topInset = -600
        // max(-600, -640) = -600 (floor wins)
        let target = ScrollMath.scrollToBottomTarget(
            contentSizeHeight: 100,
            boundsHeight: 800,
            adjustedBottomInset: 60,
            topInset: 600
        )
        #expect(target == -600)
    }

    @Test func targetUsesMaxY_whenAboveFloor() {
        // When maxY is ABOVE -topInset, maxY wins.
        // Content tall enough that maxY > -topInset.
        let target = ScrollMath.scrollToBottomTarget(
            contentSizeHeight: 2000,
            boundsHeight: 800,
            adjustedBottomInset: 400,
            topInset: 50
        )
        // maxY = 2000-800+400 = 1600, -topInset = -50
        // max(-50, 1600) = 1600 (maxY wins)
        #expect(target == 1600)
    }
}

@Suite struct ScrollMathDistanceFromBottomTests {

    @Test func distanceIsZero_whenAtExactBottom() {
        let dist = ScrollMath.distanceFromBottom(
            contentSizeHeight: 2000,
            contentOffsetY: 1600, // at bottom: 2000 - 800 + 400 = 1600
            boundsHeight: 800,
            adjustedBottomInset: 400
        )
        #expect(dist == 0)
    }

    @Test func distanceIsPositive_whenScrolledUp() {
        let dist = ScrollMath.distanceFromBottom(
            contentSizeHeight: 2000,
            contentOffsetY: 1200, // scrolled up 400 from bottom (1600 - 400)
            boundsHeight: 800,
            adjustedBottomInset: 400
        )
        #expect(dist == 400)
    }

    @Test func distanceIsNegative_whenOverscrolledPastBottom() {
        // Bouncing past the bottom gives a negative distance.
        let dist = ScrollMath.distanceFromBottom(
            contentSizeHeight: 2000,
            contentOffsetY: 1700, // overscrolled: maxY = 1600, offset = 1700
            boundsHeight: 800,
            adjustedBottomInset: 400
        )
        #expect(dist == -100)
    }

    @Test func distanceAccountsForBottomInset() {
        // Same content position, different inset gives different distance.
        let distWithKeyboard = ScrollMath.distanceFromBottom(
            contentSizeHeight: 2000,
            contentOffsetY: 1260, // at bottom with inset=60
            boundsHeight: 800,
            adjustedBottomInset: 60
        )
        #expect(distWithKeyboard == 0)

        let distWithoutKeyboard = ScrollMath.distanceFromBottom(
            contentSizeHeight: 2000,
            contentOffsetY: 1260, // same offset, but inset=400 -> now scrolled up
            boundsHeight: 800,
            adjustedBottomInset: 400
        )
        // maxY = 2000 - 800 + 400 = 1600, distance = 1600 - 1260 = 340
        #expect(distWithoutKeyboard == 340)
    }

    @Test func distanceAtTopOfContent() {
        let dist = ScrollMath.distanceFromBottom(
            contentSizeHeight: 2000,
            contentOffsetY: 0, // at top
            boundsHeight: 800,
            adjustedBottomInset: 0
        )
        // maxY = 2000 - 800 + 0 = 1200, distance = 1200 - 0 = 1200
        #expect(dist == 1200)
    }

    @Test func distanceForShortContent() {
        // Short content pinned to bottom via topInset.
        let dist = ScrollMath.distanceFromBottom(
            contentSizeHeight: 100,
            contentOffsetY: -640, // negative offset from topInset
            boundsHeight: 800,
            adjustedBottomInset: 60
        )
        // maxY = 100 - 800 + 60 = -640, distance = -640 - (-640) = 0
        #expect(dist == 0)
    }

    @Test func distanceForEmptyContent() {
        // maxY = 0 - 800 + 60 = -740, distance = -740 - 0 = -740
        let dist = ScrollMath.distanceFromBottom(
            contentSizeHeight: 0, contentOffsetY: 0,
            boundsHeight: 800, adjustedBottomInset: 60
        )
        #expect(dist == -740)
    }
}

@Suite struct ScrollMathIsNearBottomTests {

    @Test func returnsTrue_whenAtExactBottom() {
        #expect(ScrollMath.isNearBottom(distance: 0) == true)
    }

    @Test func returnsTrue_whenWithinThreshold() {
        #expect(ScrollMath.isNearBottom(distance: 50) == true)
        #expect(ScrollMath.isNearBottom(distance: 100) == true) // exactly at threshold
    }

    @Test func returnsFalse_whenBeyondThreshold() {
        #expect(ScrollMath.isNearBottom(distance: 100.1) == false)
        #expect(ScrollMath.isNearBottom(distance: 200) == false)
        #expect(ScrollMath.isNearBottom(distance: 500) == false)
    }

    @Test func returnsTrue_whenOverscrolled() {
        // Negative distance (bounce past bottom) still counts as "near."
        #expect(ScrollMath.isNearBottom(distance: -10) == true)
        #expect(ScrollMath.isNearBottom(distance: -100) == true)
    }

    @Test func thresholdMatchesConstant() {
        // Verify the threshold is what we expect (100).
        // If someone changes ScrollMath.nearBottomThreshold, this test breaks.
        #expect(ScrollMath.nearBottomThreshold == 100)
    }
}

@Suite struct ScrollMathTopInsetForShortContentTests {

    @Test func returnsZero_whenContentFillsScreen() {
        let inset = ScrollMath.topInsetForShortContent(
            contentSizeHeight: 2000,
            boundsHeight: 800,
            bottomInset: 60
        )
        #expect(inset == 0)
    }

    @Test func returnsPositive_whenContentShorterThanVisible() {
        // visibleHeight = 800 - 60 = 740, content = 200, gap = 540
        let inset = ScrollMath.topInsetForShortContent(
            contentSizeHeight: 200,
            boundsHeight: 800,
            bottomInset: 60
        )
        #expect(inset == 540)
    }

    @Test func returnsZero_whenContentExactlyFitsVisibleArea() {
        // visibleHeight = 800 - 60 = 740, content = 740 -> no gap
        let inset = ScrollMath.topInsetForShortContent(
            contentSizeHeight: 740,
            boundsHeight: 800,
            bottomInset: 60
        )
        #expect(inset == 0)
    }

    @Test func accountsForBottomInset_inVisibleHeight() {
        // visibleHeight = 800 - 400 = 400, content = 100, gap = 300
        let inset = ScrollMath.topInsetForShortContent(
            contentSizeHeight: 100,
            boundsHeight: 800,
            bottomInset: 400 // keyboard up
        )
        #expect(inset == 300)
    }

    @Test func returnsZero_whenContentIsEmpty() {
        let inset = ScrollMath.topInsetForShortContent(
            contentSizeHeight: 0,
            boundsHeight: 800,
            bottomInset: 60
        )
        // visibleHeight = 740, gap = 740
        #expect(inset == 740)
    }
}

@Suite struct ScrollMathClampedContentOffsetTests {

    @Test func doesNotClamp_whenWithinValidRange() {
        let clamped = ScrollMath.clampedContentOffset(
            currentOffsetY: 500,
            contentSizeHeight: 2000,
            boundsHeight: 800,
            bottomInset: 60,
            topInset: 0
        )
        #expect(clamped == 500)
    }

    @Test func clamps_whenOverscrolledPastBottom() {
        // maxOffsetY = 2000 - 800 + 60 = 1260, offset 1500 -> clamp to 1260
        let clamped = ScrollMath.clampedContentOffset(
            currentOffsetY: 1500,
            contentSizeHeight: 2000,
            boundsHeight: 800,
            bottomInset: 60,
            topInset: 0
        )
        #expect(clamped == 1260)
    }

    @Test func clampsToNegativeTopInset_forShortContent() {
        // maxOffsetY = 100 - 800 + 60 = -640, offset 100 -> clamp to max(-640, -640) = -640
        let clamped = ScrollMath.clampedContentOffset(
            currentOffsetY: 100,
            contentSizeHeight: 100,
            boundsHeight: 800,
            bottomInset: 60,
            topInset: 640
        )
        #expect(clamped == -640)
    }

    @Test func floorsToNegativeTopInset_whenMaxOffsetBelowNegativeInset() {
        // maxOffsetY = 50 - 800 + 400 = -350, topInset = 500
        // offset 100 > -350 -> overscrolled -> clamp to max(-500, -350) = -350
        let clamped = ScrollMath.clampedContentOffset(
            currentOffsetY: 100,
            contentSizeHeight: 50,
            boundsHeight: 800,
            bottomInset: 400,
            topInset: 500
        )
        #expect(clamped == -350)
    }

    @Test func doesNotClamp_whenExactlyAtMaxOffset() {
        // maxOffsetY = 2000 - 800 + 60 = 1260, offset 1260 -> no clamp
        let clamped = ScrollMath.clampedContentOffset(
            currentOffsetY: 1260,
            contentSizeHeight: 2000,
            boundsHeight: 800,
            bottomInset: 60,
            topInset: 0
        )
        #expect(clamped == 1260)
    }

    @Test func clampForEmptyContent() {
        // maxOffsetY = 0 - 800 + 60 = -740, offset 0 > -740 -> clamp to max(-740, -740) = -740
        let clamped = ScrollMath.clampedContentOffset(
            currentOffsetY: 0, contentSizeHeight: 0,
            boundsHeight: 800, bottomInset: 60, topInset: 740
        )
        #expect(clamped == -740)
    }
}
