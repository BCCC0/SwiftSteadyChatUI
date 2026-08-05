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
    /// The root view is the whole message wrapped in the RenderedHeightObserver
    /// (whose monotonic height drives the streaming cell's size).
    private var hostingControllers: [UUID: UIHostingController<RenderedHeightObserver<MessageBubbleView>>] = [:]
    /// The message currently streaming; used to keep the settle loop alive.
    internal var activeStreamingID: UUID?
    private var initialScrollDone = false

    /// Monotonic reported height per STREAMING message id, from the whole-message
    /// RenderedHeightObserver. The streaming cell is sized from this (never from
    /// live systemLayoutSizeFitting, which races the async render), so it grows
    /// deterministically with the render. Cleared when the message finishes.
    private var streamingHeights: [UUID: CGFloat] = [:]

    /// Committed measured height per message id (both streaming and finished).
    /// `sizeForItemAt` returns this when present so a layout pass NEVER creates a
    /// hosting controller for an off-screen item: the initial full layout of a
    /// long history would otherwise materialize a controller per message and the
    /// first eviction would tear them all down — O(total) hosting churn that
    /// pegs the main thread. Unmeasured items get an estimate; the real height
    /// lands when the cell renders (observer growth → measuredHeights).
    private var measuredHeights: [UUID: CGFloat] = [:]

    /// Cached controller-free height estimate per message id. Computing it
    /// touches the message's full text (`joined()` + `count`), which is O(total
    /// chars) — a full layout pass asks every unmeasured item, so on a 20k
    /// message history the estimate must be computed once and reused, not every
    /// tick.
    private var estimatedHeights: [UUID: CGFloat] = [:]

    /// Whether the chat auto-scrolls to the bottom on content growth. Starts
    /// following (the initial load lands at the bottom).
    internal var followState: FollowState = .following
    internal var shouldFollow: Bool { followState == .following }

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

    // MARK: - Change-driven re-measure + lazy scroll

    /// Coalesces all height-change signals (streaming render growth, thinking
    /// toggle) into ONE re-measure per runloop, then conditionally lazy-scrolls.
    private var needsReMeasure = false

    /// The whole-message RenderedHeightObserver reports the message's ideal
    /// height on every render GROWTH. Stored monotonically and used by
    /// sizeForItemAt for the streaming cell — the cell grows deterministically
    /// with the render (responsive), no live systemLayoutSizeFitting race.
    func onStreamingHeightChange(_ h: CGFloat, for id: UUID) {
        if h > (measuredHeights[id] ?? 0) { measuredHeights[id] = h }
        if h > (streamingHeights[id] ?? 0) { streamingHeights[id] = h }
        scheduleReMeasure()
    }

    /// The thinking toggle (onLayoutChange) changed the message's structure
    /// (expand/collapse) — clear the monotonic streaming height so sizeForItemAt
    /// falls back to systemLayoutSizeFitting for the current (possibly
    /// collapsed) height.
    func onBubbleHeightChanged() {
        if let streamingID = activeStreamingID {
            streamingHeights.removeValue(forKey: streamingID)
        }
        // The toggle changed the message's structure (expand/collapse): drop the
        // committed height so sizeForItemAt re-measures the (possibly collapsed)
        // height instead of returning the stale monotonic one.
        if let streamingID = activeStreamingID {
            measuredHeights.removeValue(forKey: streamingID)
        }
        scheduleReMeasure()
    }

    private func scheduleReMeasure() {
        guard !needsReMeasure else { return }
        needsReMeasure = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.needsReMeasure = false
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
            self.updateTopInsetForShortContent()
            self.maybeLazyScroll()
        }
    }

    /// Really-lazy scroll: coalesce a burst of height changes into ONE animated
    /// scroll to the bottom (only when following). A height change landing while an
    /// animation runs re-aims the same animator instead of stacking another.
    private var lazyScrollTask: Task<Void, Never>?
    private var scrollAnimator: UIViewPropertyAnimator?

    func maybeLazyScroll() {
        guard shouldFollow else { return }
        lazyScrollTask?.cancel()
        lazyScrollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            guard self.shouldFollow else { return }
            self.collectionView.layoutIfNeeded()
            let inset = self.collectionView.adjustedContentInset
            let targetY = ScrollMath.scrollToBottomTarget(
                contentSizeHeight: self.collectionView.contentSize.height,
                boundsHeight: self.collectionView.bounds.height,
                adjustedBottomInset: inset.bottom,
                topInset: inset.top
            )
            if let animator = self.scrollAnimator {
                animator.stopAnimation(false)
                animator.finishAnimation(at: .current)
            }
            let animator = UIViewPropertyAnimator(duration: 0.2, curve: .easeOut) {
                self.collectionView.contentOffset.y = targetY
            }
            self.scrollAnimator = animator
            animator.startAnimation()
        }
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

    func updateStreamingState() {
        // A message is streaming while any reply-class block is unfinished. A
        // `.user` block is always finished, so only thinking/reply stream.
        activeStreamingID = messages.last(where: { $0.blocks.contains { $0.kind != .user && !$0.isStreamFinished } })?.id
        // Drop the monotonic height for messages that finished (or were
        // removed) — the finished cell re-measures via systemLayoutSizeFitting.
        // Streaming messages keep their observer-driven height.
        streamingHeights = streamingHeights.filter { id, _ in
            messages.first(where: { $0.id == id })?.isStreamFinished == false
        }
        // The settle loop re-measures NON-streaming async content (initial load,
        // static markdown parse on append, the finished message on finish).
        // Streaming growth is driven by the RenderedHeightObserver → the stored
        // height, so the loop must not spin during a stream.
        if activeStreamingID == nil {
            scheduleSettle()
        }
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
        let width = collectionView.bounds.width
        // Streaming cell: size it from the observer's monotonic height (the
        // render's committed height) — NOT systemLayoutSizeFitting, which races
        // the async render and never reflects the streamed content. The cell is
        // responsive (grows with each render), top-aligned, growing downward.
        if !msg.isStreamFinished, let h = streamingHeights[msg.id] {
            return CGSize(width: width, height: max(h, 1))
        }
        // Already measured (streaming finished or static parsed): reuse without
        // touching the hosting-controller cache. This is what keeps a full
        // layout pass over a long history cheap — sizeForItemAt is called for
        // far more items than are visible, and creating a controller per item is
        // O(total) hosting churn (the 20k-message freeze).
        if let h = measuredHeights[msg.id] {
            return CGSize(width: width, height: max(h, 1))
        }
        // Unmeasured: return a controller-free estimate. The committed height
        // lands when the cell actually renders: cellForItemAt creates the
        // controller, whose whole-message RenderedHeightObserver reports growth
        // into measuredHeights (→ scheduleReMeasure → re-layout). Measuring here
        // would force a hosting-controller creation per item during every full
        // layout pass.
        return estimatedSize(for: msg, width: width)
    }

    /// Controller-free height estimate for an unmeasured message. Only needs to
    /// yield a scrollable contentSize; the committed height replaces it once the
    /// cell renders (observer growth → measuredHeights). Cached: a full layout
    /// pass asks every unmeasured item, and computing the estimate touches the
    /// full text, so it must not be re-done per tick on a long history.
    private func estimatedSize(for msg: StreamingMessage, width: CGFloat) -> CGSize {
        let h: CGFloat
        if let cached = estimatedHeights[msg.id] {
            h = cached
        } else {
            let text = msg.blocks.compactMap { $0.content }.joined()
            let charsPerLine = max(20, Int(width / 10))
            let lines = max(1, text.count / charsPerLine)
            h = CGFloat(lines) * 22 + 40
            estimatedHeights[msg.id] = h
        }
        return CGSize(width: width, height: h)
    }

    // MARK: Cached hosting controller

    /// Builds the message's hosting root view: the whole message wrapped in a
    /// RenderedHeightObserver whose onGeometryChange reports the message's TOTAL
    /// ideal height on every render growth, driving the streaming cell's height.
    /// Carries the `streamingAnimateText` config knob into the bubble.
    private func makeRootView(
        for message: StreamingMessage
    ) -> RenderedHeightObserver<MessageBubbleView> {
        RenderedHeightObserver(
            content: MessageBubbleView(
                message: message,
                animateStreamingText: config.streamingAnimateText,
                onLayoutChange: { [weak self] in self?.onBubbleHeightChanged() }
            )
        ) { [weak self] h in
            self?.onStreamingHeightChange(h, for: message.id)
        }
    }

    func hostingController(for message: StreamingMessage) -> UIHostingController<RenderedHeightObserver<MessageBubbleView>> {
        if let existing = hostingControllers[message.id] {
            return existing
        }
        let host = UIHostingController(rootView: makeRootView(for: message))
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

extension ChatCollectionViewController {
    /// Public API: override the send button's enabled state. Pass `nil` to
    /// restore the text-driven default. Lets a consumer pin the send button
    /// (e.g. disable it while the service is busy) and reset it when they want.
    public func setSendEnabled(_ enabled: Bool?) {
        inputBar.setSendEnabled(enabled)
    }
}

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
        if config.dismissKeyboardOnSend { view.endEditing(true) }
        followState = FollowState.transition(current: followState, event: .reengage)
        scrollToBottom(animated: false)
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

    @objc func didTapScrollToBottom() {
        followState = FollowState.transition(current: followState, event: .reengage)
        scrollToBottom(animated: true)
        updateFABVisibility()
    }

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
        // Message id → index map, built ONCE per eviction (O(messages)). The
        // previous per-controller `first(where:)`/`firstIndex(where:)` scans
        // were O(messages) for EVERY cached controller on EVERY settle tick —
        // on a long history (20k messages) that dominated the main thread.
        var indexByID: [UUID: Int] = [:]
        indexByID.reserveCapacity(messages.count)
        for (i, m) in messages.enumerated() { indexByID[m.id] = i }

        // 1. Deletion/regeneration: evict ids no longer in the message list.
        let staleIDs = hostingControllers.keys.filter { indexByID[$0] == nil }
        for id in staleIDs {
            evict(id)
        }

        // 2. Finished messages whose cell frame is outside the visible window.
        //    Skip the (comparatively expensive) window scan when the cache is
        //    already bounded — nothing meaningful to evict.
        guard hostingControllers.count > 32 else { return }
        let visibleWindow = collectionView.bounds.insetBy(dx: 0, dy: -2000)
        let offWindowIDs = hostingControllers.keys.filter { id in
            guard let index = indexByID[id],
                  index < messages.count,
                  messages[index].isStreamFinished,
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
