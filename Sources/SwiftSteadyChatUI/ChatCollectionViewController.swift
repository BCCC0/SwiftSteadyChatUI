import UIKit
import SwiftUI
import SwiftStreamingMarkdown

// Cached-hosting-controller pattern: one UIHostingController<MessageBubbleView> is
// cached per message UUID and OUTLIVES the cell. The collection cell merely hosts
// the cached hosting view. Because the chat service streams text through the
// ChatStreamSource AsyncStream (the messages array is static during streaming),
// the collection view never reloads mid-stream — the StreamedMarkdownView's
// @StateObject controller keeps its iterator and re-renders in place.
//
// The keyboard handling (contentInset + keyboardLayoutGuide + ScrollMath), the
// settle loop, and the scroll-follow math are extracted into same-module files
// (SettleLoop.swift, KeyboardHandling.swift, BottomInset.swift, ScrollFollow.swift,
// HostedContentCell.swift). Because Swift `private` is file-scoped, the stored
// properties and helpers those cross-file extensions touch are widened to
// `internal` (non-public, not API).

@MainActor
public final class ChatCollectionViewController: UIViewController {

    internal let collectionView: UICollectionView
    internal let inputBar = ChatInputBar()
    private let scrollToBottomButton = ScrollToBottomButton()
    internal var keyboardObserver: NSObjectProtocol?
    /// Token for the keyboardWillShow observer — stored so it can be removed
    /// in deinit alongside `keyboardObserver` (keyboardWillChangeFrame).
    internal var keyboardWillShowObserver: NSObjectProtocol?
    internal var settleLink: CADisplayLink?
    internal var settleTicks = 0
    internal var stableTicks = 0
    internal var lastContentHeight: CGFloat = -1

    private let service: any ChatService
    /// Test-visible message list (not API). The sync-diffing tests assert on it.
    internal var messages: [StreamingMessage] = []
    internal var config: ChatUIConfig

    /// Cached per-message hosting controllers — the heart of the pattern.
    /// Keyed by message UUID so the StreamedMarkdownView survives cell reuse.
    private var hostingControllers: [UUID: UIHostingController<MessageBubbleView>] = [:]
    /// The message currently streaming; used to keep the settle loop alive.
    internal var activeStreamingID: UUID?
    private var initialScrollDone = false
    /// True once the user drags the collection view (stops auto-follow-bottom).
    internal var userScrolled = false

    public init(service: any ChatService, config: ChatUIConfig = .init()) {
        self.service = service
        self.config = config
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = config.messageSpacing
        layout.sectionInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Test-visible message count (not API).
    internal var numberOfMessages: Int { messages.count }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupCollectionView()
        setupInputBar()
        setupFAB()
        setupGestures()
        observeKeyboard()

        messages = service.messages
        service.onMessagesChanged = { [weak self] in self?.syncFromService() }
        updateStreamingState()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let preserve = isNearBottom()
        updateBottomInset(animated: false, preserveBottom: preserve)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !initialScrollDone else { return }
        initialScrollDone = true
        collectionView.layoutIfNeeded()
        updateTopInsetForShortContent()
        scrollToBottom(animated: false)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopSettleLink()
    }

    deinit {
        if let ob = keyboardObserver { NotificationCenter.default.removeObserver(ob) }
        if let ob = keyboardWillShowObserver { NotificationCenter.default.removeObserver(ob) }
        settleLink?.invalidate()
        settleLink = nil
    }
}

// MARK: - Service sync

private extension ChatCollectionViewController {

    func syncFromService() {
        let wasNearBottom = isNearBottom()
        let oldCount = messages.count
        messages = service.messages
        let delta = messages.count - oldCount

        if delta > 0 {
            // Append: insert only the new items — never reloadData.
            let indexPaths = (oldCount..<messages.count).map { IndexPath(item: $0, section: 0) }
            collectionView.performBatchUpdates {
                collectionView.insertItems(at: indexPaths)
            } completion: { [weak self] _ in
                self?.finishLayoutPass(preserveBottom: wasNearBottom)
            }
        } else if delta < 0 {
            // Delete: remove the dropped items so the collection view's item
            // count stays consistent with the data source.
            // NOTE: this assumes tail-only deletions — the dropped messages
            // are `(messages.count..<oldCount)`, i.e. the trailing slice. The
            // chat service contract (static mid-stream array, append-only
            // conversation) guarantees this. A future non-tail shrink (e.g.
            // mid-list removal) would need real index math to map the removed
            // messages' positions to IndexPaths instead of assuming the tail.
            let indexPaths = (messages.count..<oldCount).map { IndexPath(item: $0, section: 0) }
            collectionView.performBatchUpdates {
                collectionView.deleteItems(at: indexPaths)
            } completion: { [weak self] _ in
                self?.finishLayoutPass(preserveBottom: wasNearBottom)
            }
        } else {
            // Structural change without append (stream finished, placeholder
            // replaced). No cell ops — the cached hosting controller keeps the
            // StreamedMarkdownView; one re-measure finalizes the height.
            collectionView.collectionViewLayout.invalidateLayout()
            finishLayoutPass(preserveBottom: wasNearBottom)
        }
        updateStreamingState()
        if delta <= 0 {
            // Delete/regenerate: drop cached controllers whose message no
            // longer exists (deletion) or whose finished cell scrolled out of
            // the eviction window (regeneration re-creates fresh on next view).
            evictCachedControllers()
        }
    }

    func finishLayoutPass(preserveBottom: Bool) {
        collectionView.layoutIfNeeded()
        updateTopInsetForShortContent()
        updateBottomInset(animated: false, preserveBottom: preserveBottom)
        if preserveBottom { scrollToBottom(animated: false) }
    }

    /// Track the streaming message and kick off the settle loop (any message
    /// change can produce async content — MarkdownView parses, streamed text —
    /// whose cell heights must be re-measured until the layout is stable).
    func updateStreamingState() {
        // A message is streaming while any of its blocks is unfinished. A `.user`
        // block is always finished, so only reply-class blocks can stream.
        activeStreamingID = messages.last(where: { $0.blocks.contains { !$0.isStreamFinished } })?.id
        scheduleSettle()
    }
}

// MARK: - CollectionView

extension ChatCollectionViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func setupCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(HostedContentCell.self, forCellWithReuseIdentifier: "hostCell")
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        messages.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "hostCell", for: indexPath) as! HostedContentCell
        let msg = messages[indexPath.item]
        cell.attach(hostingController(for: msg).view)
        return cell
    }

    public func collectionView(_ collectionView: UICollectionView,
                               layout collectionViewLayout: UICollectionViewLayout,
                               sizeForItemAt indexPath: IndexPath) -> CGSize {
        let msg = messages[indexPath.item]
        let host = hostingController(for: msg)
        let width = collectionView.bounds.width
        let fitting = host.view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: max(fitting.height, 1))
    }

    // MARK: Cached hosting controller

    func hostingController(for message: StreamingMessage) -> UIHostingController<MessageBubbleView> {
        if let existing = hostingControllers[message.id] {
            return existing
        }
        let host = UIHostingController(rootView: MessageBubbleView(message: message))
        host.sizingOptions = .intrinsicContentSize
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        // Fixed width lets sizeForItemAt measure a detached (not-yet-attached)
        // hosting view correctly; matches the full-width cell layout.
        let width = collectionView.bounds.width > 0 ? collectionView.bounds.width : UIScreen.main.bounds.width
        host.view.widthAnchor.constraint(equalToConstant: width).isActive = true
        hostingControllers[message.id] = host
        return host
    }
}

// MARK: - InputBar

private extension ChatCollectionViewController {
    func setupInputBar() {
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputBar)

        let keyboardGuide = view.keyboardLayoutGuide
        keyboardGuide.followsUndockedKeyboard = false

        NSLayoutConstraint.activate([
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: keyboardGuide.topAnchor)
        ])

        inputBar.onSend = { [weak self] text in self?.submit(text) }
        inputBar.onHeightChanged = { [weak self] in
            guard let self else { return }
            let preserve = self.isNearBottom()
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
            self.updateBottomInset(animated: true, preserveBottom: preserve)
        }
    }

    func submit(_ text: String) {
        guard !text.isEmpty else { return }
        inputBar.clear()
        if config.dismissKeyboardOnSend {
            view.endEditing(true) // dismiss the keyboard on send (standard chat UX)
        }
        Task { await service.sendMessage(text) }
    }
}

// MARK: - FAB

extension ChatCollectionViewController {
    func setupFAB() {
        guard config.showsScrollToBottomButton else { return }
        scrollToBottomButton.addTarget(self, action: #selector(didTapScrollToBottom), for: .touchUpInside)
        view.addSubview(scrollToBottomButton)

        NSLayoutConstraint.activate([
            scrollToBottomButton.widthAnchor.constraint(equalToConstant: 44),
            scrollToBottomButton.heightAnchor.constraint(equalToConstant: 44),
            scrollToBottomButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollToBottomButton.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -12)
        ])
    }

    @objc func didTapScrollToBottom() { scrollToBottom(animated: true); updateFABVisibility() }

    func updateFABVisibility() {
        let show = !isNearBottom()
        UIView.animate(withDuration: 0.18, delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.scrollToBottomButton.alpha = show ? 1 : 0
        }
    }
}

// MARK: - Gestures

private extension ChatCollectionViewController {
    func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapBackground))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        collectionView.addGestureRecognizer(tap)
    }
    @objc func didTapBackground() { view.endEditing(true) }
}

extension ChatCollectionViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIControl)
    }
}

// MARK: - Debug hooks (test-visible, not API)

extension ChatCollectionViewController {

    /// Force-populate the hosting-controller cache for every message.
    /// Test-only; real population happens lazily via cell/measure calls.
    internal func debugWarmCacheForAllMessages() {
        for message in messages {
            _ = hostingController(for: message)
        }
    }

    /// Number of hosting controllers currently cached.
    internal var debugCachedControllerCount: Int {
        hostingControllers.count
    }

    /// Run one settle pass (the same work a display-link tick performs) so a
    /// test can drive layout + eviction deterministically without a run loop.
    internal func debugCompleteSettle() {
        settleTick()
        evictCachedControllers()
    }
}

// MARK: - Cache eviction (bounded cache)

extension ChatCollectionViewController {

    /// Bounded-cache eviction: runs on every settle tick and after
    /// delete/regenerate syncs so the hosting-controller cache cannot grow
    /// without bound over a long chat.
    ///
    /// Eviction window: a controller is evicted only when its message is fully
    /// finished streaming AND its cell frame lies outside a window around the
    /// visible bounds (`collectionView.bounds.insetBy(dx: 0, dy: -2000)`, i.e.
    /// ±2000 pt above/below the visible rect). The generous window preserves
    /// the no-flicker invariant:
    ///   - every visible cell's controller is retained (a visible cell's frame
    ///     is always inside the window);
    ///   - a streaming message is never evicted regardless of position (its
    ///     StreamedMarkdownView would lose its iterator and the in-place
    ///     re-render would restart mid-stream).
    /// When a cell's frame can't be determined (layout not yet computed) we
    /// keep the controller — the next settle tick re-evaluates with fresh
    /// layout attributes.
    ///
    /// Deletion/regeneration: any cached id no longer present in `messages`
    /// is always evicted, regardless of stream state.
    internal func evictCachedControllers() {
        // 1. Deletion/regeneration: evict ids no longer in the message list.
        let liveIDs = Set(messages.map(\.id))
        let staleIDs = hostingControllers.keys.filter { !liveIDs.contains($0) }
        for id in staleIDs {
            evict(id)
        }

        // 2. Finished messages whose cell frame is outside the visible window.
        let visibleWindow = collectionView.bounds.insetBy(dx: 0, dy: -2000)
        let offWindowIDs = hostingControllers.keys.filter { id in
            guard let message = messages.first(where: { $0.id == id }) else { return false }
            guard message.isStreamFinished else { return false }
            guard let index = messages.firstIndex(where: { $0.id == id }),
                  let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame
            else {
                return false // unknown frame — keep (conservative, no-flicker)
            }
            return !frame.intersects(visibleWindow)
        }
        for id in offWindowIDs {
            evict(id)
        }
    }

    /// Remove a cached controller and detach its hosted view from any cell
    /// still hosting it, so a recycled cell never holds a strong reference to
    /// an evicted controller. No-op when the id isn't cached.
    private func evict(_ id: UUID) {
        guard let host = hostingControllers.removeValue(forKey: id) else { return }
        host.view.removeFromSuperview()
    }
}
