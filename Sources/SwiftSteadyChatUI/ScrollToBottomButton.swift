import UIKit

/// Floating action button that appears when the user scrolls away from the
/// bottom of the conversation. Extracted from the chat controller's FAB.
///
/// Starts at `alpha = 0`; the hosting controller reveals it (animated) when
/// the user is no longer near the bottom of the conversation.
public final class ScrollToBottomButton: UIButton {

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public convenience init() {
        self.init(frame: .zero)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setImage(UIImage(systemName: "arrow.down"), for: .normal)
        tintColor = .label
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 22
        alpha = 0
        accessibilityLabel = "Scroll to bottom"
        accessibilityIdentifier = "scroll-to-bottom"
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: 44, height: 44)
    }
}
