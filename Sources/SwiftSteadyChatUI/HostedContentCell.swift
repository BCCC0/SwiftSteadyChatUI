import UIKit

// MARK: - Cell that hosts a cached SwiftUI view

final class HostedContentCell: UICollectionViewCell {
    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.subviews.forEach { $0.removeFromSuperview() }
    }

    func attach(_ hostedView: UIView) {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            hostedView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        ])
    }
}
