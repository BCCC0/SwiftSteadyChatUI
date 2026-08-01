import UIKit

// MARK: - Keyboard

extension ChatCollectionViewController {
    func observeKeyboard() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.isNearBottom() {
                self.scrollToBottom(animated: false)
            }
        }

        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil, queue: .main
        ) { [weak self] n in self?.handleKeyboard(n) }
    }

    func handleKeyboard(_ notification: Notification) {
        let preserve = isNearBottom()
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0.25
        let curveRaw = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16).union([.beginFromCurrentState, .allowUserInteraction])

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
            let inset = self.currentRequiredBottomInset()
            self.collectionView.contentInset.bottom = inset
            self.collectionView.verticalScrollIndicatorInsets.bottom = inset
            self.updateTopInsetForShortContent()
            if preserve { self.scrollToBottom(animated: false) }
        }
    }
}
