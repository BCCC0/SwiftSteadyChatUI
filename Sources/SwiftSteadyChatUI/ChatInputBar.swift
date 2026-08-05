import UIKit

public final class ChatInputBar: UIView {

    public var onSend: ((String) -> Void)?
    public var onHeightChanged: (() -> Void)?

    private let textView = UITextView()
    private let sendButton = UIButton(type: .system)

    private var textViewHeightConstraint: NSLayoutConstraint?
    /// When set, wins over the text-driven default so a consumer can pin the
    /// send button (e.g. disabled while the service is busy). `nil` = enabled
    /// iff the text view has text.
    private var sendEnabledOverride: Bool?

    /// Public API: override the send button's enabled state. Pass `nil` to
    /// restore the text-driven default. Lets the consumer reset the button
    /// (e.g. disable it while a reply is streaming) whenever they want.
    public func setSendEnabled(_ enabled: Bool?) {
        sendEnabledOverride = enabled
        updateSendButtonState()
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = .systemBackground
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: -2)

        textView.isScrollEnabled = false
        textView.delegate = self
        textView.font = .preferredFont(forTextStyle: .body)
        textView.accessibilityIdentifier = "input-textview"
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        textView.layer.cornerRadius = 20
        textView.backgroundColor = UIColor.tertiarySystemFill.withAlphaComponent(0.3)
        textView.translatesAutoresizingMaskIntoConstraints = false

        sendButton.setImage(UIImage(systemName: "arrow.up"), for: .normal)
        sendButton.tintColor = .white
        sendButton.backgroundColor = .systemGray
        sendButton.layer.cornerRadius = 18
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.accessibilityIdentifier = "send-button"
        sendButton.addTarget(self, action: #selector(didTapSend), for: .touchUpInside)

        addSubview(textView)
        addSubview(sendButton)

        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: 36)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textViewHeightConstraint!,

            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        updateSendButtonState()
    }

    public func clear() {
        textView.text = ""
        updateTextViewHeight()
        updateSendButtonState()
    }

    @objc private func didTapSend() {
        guard let text = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        onSend?(text)
    }

    private func updateSendButtonState() {
        let hasText = !(textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        let enabled = sendEnabledOverride ?? hasText
        sendButton.isEnabled = enabled
        sendButton.backgroundColor = enabled ? .systemBlue : .systemGray
    }

    private func updateTextViewHeight() {
        let maxHeight: CGFloat = 120
        let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        let newHeight = min(max(size.height, 36), maxHeight)
        textViewHeightConstraint?.constant = newHeight
        textView.isScrollEnabled = size.height > maxHeight
    }
}

extension ChatInputBar: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        updateSendButtonState()
        let oldHeight = textViewHeightConstraint?.constant ?? 36
        updateTextViewHeight()
        let newHeight = textViewHeightConstraint?.constant ?? 36
        if abs(oldHeight - newHeight) > 0.5 {
            onHeightChanged?()
        }
    }
}
