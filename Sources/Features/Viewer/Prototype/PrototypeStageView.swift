import UIKit

/// The native prototype player's stage: one zoomable viewport per board, swapped with
/// Penpot's transitions (``PrototypeTransition``), with Penpot's overlays on top. What a
/// tap runs comes from ``PrototypeModel``; the boards are the on-device vector renders the
/// board detail shows (``BoardRenders/vector(of:exporterFallback:)``), so a design system
/// plays without Penpot's web app and its memory.
@MainActor
final class PrototypeStageView: UIView {
    var onLoadingChange: (Bool) -> Void = { _ in }
    var onBoardChange: (String) -> Void = { _ in }
    var onOpenURL: (URL) -> Void = { _ in }
    var onRenderFailed: () -> Void = {}
    var onExitFullScreen: () -> Void = {}
    /// The counter was tapped: show the page's boards (Penpot's thumbnails panel).
    var onShowBoards: () -> Void = {}
    var onSelectThread: (CommentThread) -> Void = { _ in }
    /// A tap on the board in comments mode: the position on the page and the board.
    var onPlaceComment: (Point, String) -> Void = { _, _ in }
    /// A pin dropped on the board: its new position on the page and the board.
    var onMoveThread: (CommentThread, Point, String) -> Void = { _, _, _ in }

    /// Penpot's comments mode (`viewer/comments.cljs`): the board's threads show as pins,
    /// and a tap on the board places a new comment instead of running the prototype; delays
    /// wait. Pins sit in a layer of their own, in screen space, like the page canvas'.
    var isCommenting = false {
        didSet { if isCommenting != oldValue { updatePins() } }
    }

    /// The page's threads, filtered; those on the board shown appear in comments mode.
    var threads: [CommentThread] = [] {
        didSet { updatePins() }
    }

    /// Full screen has no close button over the design: touching and holding the
    /// prototype with two fingers for two seconds ends it. A hint says so when full screen
    /// starts. VoiceOver takes those touches for its own gestures, so there its escape
    /// gesture (a two-finger scrub) ends full screen instead.
    var isFullScreen = false {
        didSet {
            guard isFullScreen != oldValue else { return }
            exitHold.isEnabled = isFullScreen
            if isFullScreen { showFullScreenHint() } else { hideFullScreenHint(animated: false) }
        }
    }

    /// Penpot's pagination (`viewer-pagination`): the previous and next board at the sides,
    /// and at the bottom a button back to the first board beside the counter. Penpot slides
    /// it away in full screen until the pointer comes near; a touch screen has no pointer,
    /// so the player's menu shows or hides it, in full screen too.
    var showsNavigation = true {
        didSet { if showsNavigation != oldValue { updateNavigation() } }
    }

    /// Right to left, the previous board's button is on the right and points there.
    var isRightToLeft = false {
        didSet {
            guard isRightToLeft != oldValue else { return }
            previousButton.configuration?.image = Self.icon(isRightToLeft ? "ic-arrow-right" : "ic-arrow-left", size: 18)
            nextButton.configuration?.image = Self.icon(isRightToLeft ? "ic-arrow-left" : "ic-arrow-right", size: 18)
            setNeedsLayout()
        }
    }

    /// A second stage showing what this one does, on an external display
    /// (``ExternalDisplay``): every board with its transition, the overlays and the
    /// scrolling follow there, drawn from the same renders. It takes no input.
    weak var mirror: PrototypeStageView? {
        didSet { if mirror !== oldValue { syncMirror() } }
    }

    private lazy var exitHold: UILongPressGestureRecognizer = {
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(heldToExit(_:)))
        hold.numberOfTouchesRequired = 2
        hold.minimumPressDuration = 2
        hold.cancelsTouchesInView = false
        hold.delegate = self
        hold.isEnabled = false
        return hold
    }()
    /// A swipe pages like the side buttons, against the reading direction towards the
    /// next board, and the boards push each other along. Not where the board is wider
    /// than the screen: there a swipe scrolls it.
    private lazy var swipes: [UISwipeGestureRecognizer] = {
        let directions: [UISwipeGestureRecognizer.Direction] = [.left, .right]
        return directions.map { direction in
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            swipe.delegate = self
            return swipe
        }
    }()
    private let fullScreenHint = PaddedLabel()
    private let pinLayer = PinLayerView()
    private var pinViews: [String: CommentPinTile] = [:]
    private var draggedPinID: String?
    private var hideHintTask: Task<Void, Never>?
    private var previousButton: UIButton!
    private var nextButton: UIButton!
    private var firstButton: UIButton!
    private let counter = PaddedLabel()
    private var controls: [UIView] { [previousButton, nextButton, firstButton, counter, fullScreenHint] }

    @objc private func heldToExit(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, isFullScreen else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onExitFullScreen()
    }

    @objc private func swiped(_ recognizer: UISwipeGestureRecognizer) {
        let towardsLeft = recognizer.direction == .left
        let transition = PrototypeTransition(kind: .push, direction: CGVector(dx: towardsLeft ? -1 : 1, dy: 0),
                                             duration: 0.3,
                                             controlPoints: PrototypeTransition.controlPoints("ease-out"),
                                             offsetEffect: false)
        step(by: towardsLeft != isRightToLeft ? 1 : -1, transition: transition)
    }

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer is UISwipeGestureRecognizer else { return super.gestureRecognizerShouldBegin(recognizer) }
        guard let current, !busy else { return false }
        return current.contentSize.width <= current.bounds.width + 1
    }

    override func accessibilityPerformEscape() -> Bool {
        guard isFullScreen else { return false }
        onExitFullScreen()
        return true
    }

    private func showFullScreenHint() {
        hideHintTask?.cancel()
        fullScreenHint.layer.removeAllAnimations()
        fullScreenHint.alpha = 0
        fullScreenHint.isHidden = false
        bringSubviewToFront(fullScreenHint)
        UIView.animate(withDuration: 0.2) { self.fullScreenHint.alpha = 1 }
        hideHintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.hideFullScreenHint(animated: true)
        }
    }

    private func hideFullScreenHint(animated: Bool) {
        hideHintTask?.cancel()
        guard animated else {
            fullScreenHint.layer.removeAllAnimations()
            fullScreenHint.isHidden = true
            return
        }
        UIView.animate(withDuration: 0.4) {
            self.fullScreenHint.alpha = 0
        } completion: { finished in
            if finished { self.fullScreenHint.isHidden = true }
        }
    }

    /// Penpot's secondary icon button: the page's color with a hairline, the icon in the
    /// secondary foreground, the accent while pressed (Penpot's hover).
    private func makeNavigationButton(_ icon: String, label: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = Self.icon(icon, size: 18)
        configuration.contentInsets = .zero
        configuration.background.backgroundColor = .penpotPage
        configuration.background.strokeColor = .penpotSurface
        configuration.background.strokeWidth = 1
        configuration.background.cornerRadius = 8
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.configurationUpdateHandler = { button in
            button.configuration?.baseForegroundColor = button.isHighlighted ? .penpotAccent : .penpotForegroundSecondary
        }
        button.accessibilityLabel = label
        button.isHidden = true
        return button
    }

    /// One of the app's Penpot icons as a template image of `size` points.
    private static func icon(_ name: String, size: CGFloat) -> UIImage? {
        guard let image = UIImage(named: name) else { return nil }
        let side = CGSize(width: size, height: size)
        return UIGraphicsImageRenderer(size: side).image { _ in
            image.draw(in: CGRect(origin: .zero, size: side))
        }.withRenderingMode(.alwaysTemplate)
    }

    var zoom: PrototypeZoom = .fit {
        didSet {
            guard zoom != oldValue else { return }
            current?.apply(zoom, animated: true)
            mirror?.zoom = zoom
        }
    }

    private var model: PrototypeModel?
    private var renders: BoardRenders?
    private(set) var current: BoardViewport?
    /// Boards to go back to (`prev-screen`), the last one on top.
    private var history: [String] = []
    private var documents: [String: CGPDFDocument] = [:]
    private var loads: [String: Task<CGPDFDocument?, Never>] = [:]
    private var awaitedLoads = 0
    /// `after-delay` interactions waiting, keyed by the board or overlay they belong to.
    private var delayed: [String: [Task<Void, Never>]] = [:]
    /// A board or an overlay is loading, or a transition is running: taps wait, as in
    /// Penpot, where the viewer ignores interactions until `complete-animation`.
    private var busy = false
    /// Bumped by ``play(_:renders:from:)``: work of an earlier page or start is dropped.
    private var generation = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .clear
        previousButton = makeNavigationButton("ic-arrow-left", label: .appLocalized("Previous")) { [weak self] in
            self?.step(by: -1)
        }
        nextButton = makeNavigationButton("ic-arrow-right", label: .appLocalized("Next")) { [weak self] in
            self?.step(by: 1)
        }
        firstButton = makeNavigationButton(AppIcon.restore.assetName, label: .appLocalized("Go to the first board")) { [weak self] in
            self?.goToFirstBoard()
        }
        counter.font = WorkSans.uiFont(for: .regular, size: 13)
        counter.textColor = .penpotForegroundSecondary
        counter.backgroundColor = .penpotPage
        counter.textAlignment = .center
        counter.layer.cornerRadius = 8
        counter.layer.masksToBounds = true
        counter.isHidden = true
        counter.isUserInteractionEnabled = true
        counter.accessibilityTraits = .button
        counter.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(counterTapped)))
        fullScreenHint.text = .appLocalized("Touch and hold with two fingers for 2 seconds to leave full screen.")
        fullScreenHint.font = WorkSans.uiFont(for: .regular, size: 13)
        fullScreenHint.textColor = .label
        fullScreenHint.numberOfLines = 0
        fullScreenHint.textAlignment = .center
        fullScreenHint.backgroundColor = UIColor.penpotPage.withAlphaComponent(0.92)
        fullScreenHint.layer.cornerRadius = 8
        fullScreenHint.layer.masksToBounds = true
        fullScreenHint.insets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        fullScreenHint.isUserInteractionEnabled = false
        fullScreenHint.isHidden = true
        addSubview(pinLayer)
        controls.forEach(addSubview)
        addGestureRecognizer(exitHold)
        swipes.forEach(addGestureRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Starts playing `model` at `boardID`, forgetting the way back.
    func play(_ model: PrototypeModel, renders: BoardRenders, from boardID: String) {
        generation += 1
        cancelAllDelays()
        busy = false
        history = []
        self.model = model
        self.renders = renders
        show(boardID, transition: .instant, preserveScroll: false, remember: false)
    }

    /// The page changed live (``LiveFile``): what is drawn at another revision now is drawn
    /// again, and the board on screen shows again in place, its scroll kept, the way back
    /// too. A board that is gone gives way to the start.
    func update(_ model: PrototypeModel, renders: BoardRenders) {
        let old = self.renders
        self.model = model
        self.renders = renders
        for id in Array(documents.keys) where old?.revision(for: id) != renders.revision(for: id) {
            documents[id] = nil
        }
        guard let id = current?.boardID, !busy else { return }
        if model.board(id) != nil {
            show(id, transition: .instant, preserveScroll: true, remember: false)
        } else if let start = model.startBoard(preferred: nil) {
            show(start, transition: .instant, preserveScroll: false, remember: false)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Not `frame`: during a transition the viewports carry a transform, and setting the
        // frame then moves their centre to undo it. A scroll view's `bounds.origin` is its
        // scroll position, so only the size is set.
        for case let viewport as BoardViewport in subviews {
            viewport.center = CGPoint(x: bounds.midX, y: bounds.midY)
            if viewport.bounds.size != bounds.size { viewport.bounds.size = bounds.size }
        }
        layoutControls()
        pinLayer.frame = bounds
        bringSubviewToFront(pinLayer)
        controls.forEach(bringSubviewToFront)
        positionPins()
    }

    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        // A board added for a transition must not cover the pins or the buttons.
        if subview is BoardViewport {
            bringSubviewToFront(pinLayer)
            controls.forEach(bringSubviewToFront)
        }
    }

    // MARK: Navigation

    /// Penpot's sizes (`viewer.scss`: 32×64 side buttons, a 28×32 button and a 64×32
    /// counter at the bottom, 8 from the edges) at 1.2×, as the app's other Penpot
    /// controls are for touch.
    private func layoutControls() {
        let insets = safeAreaInsets
        let leading = isRightToLeft ? bounds.maxX - insets.right - 8 : bounds.minX + insets.left + 8
        let trailing = isRightToLeft ? bounds.minX + insets.left + 8 : bounds.maxX - insets.right - 8
        func place(_ view: UIView, at edge: CGFloat, width: CGFloat, height: CGFloat, y: CGFloat, fromLeading: Bool) {
            let towardsRight = fromLeading != isRightToLeft
            view.frame = CGRect(x: towardsRight ? edge : edge - width, y: y, width: width, height: height)
        }
        let side = CGSize(width: 38, height: 76)
        let middle = bounds.midY - side.height / 2
        place(previousButton, at: leading, width: side.width, height: side.height, y: middle, fromLeading: true)
        place(nextButton, at: trailing, width: side.width, height: side.height, y: middle, fromLeading: false)
        let bottom = bounds.maxY - insets.bottom - 8 - 38
        place(firstButton, at: leading, width: 34, height: 38, y: bottom, fromLeading: true)
        let counterWidth = max(76, counter.intrinsicContentSize.width)
        counter.frame = CGRect(x: bounds.midX - counterWidth / 2, y: bottom, width: counterWidth, height: 38)
        let hintWidth = min(bounds.width - insets.left - insets.right - 32, 340)
        let hintSize = fullScreenHint.sizeThatFits(CGSize(width: hintWidth, height: .greatestFiniteMagnitude))
        fullScreenHint.frame = CGRect(x: bounds.midX - hintSize.width / 2, y: insets.top + 16,
                                      width: hintSize.width, height: hintSize.height)
    }

    /// Shows the buttons a board has: no previous one on the first, no next one on the last,
    /// none on a board that isn't in the viewer's list (hidden in it, reached by a link).
    private func updateNavigation() {
        let boards = model?.viewerBoards ?? []
        let index = current.flatMap { boards.firstIndex(of: $0.boardID) }
        let visible = showsNavigation && current != nil && !boards.isEmpty
        previousButton.isHidden = !visible || (index ?? 0) == 0
        nextButton.isHidden = !visible || index.map { $0 + 1 >= boards.count } ?? true
        firstButton.isHidden = !visible
        counter.isHidden = !visible || index == nil
        if let index {
            counter.text = "\((index + 1).formatted()) / \(boards.count.formatted())"
        }
        setNeedsLayout()
    }

    /// The previous or next board of the viewer's list, as Penpot's buttons and arrow keys
    /// go: at once, no transition (a swipe pushes), overlays closed, and remembered for
    /// going back.
    private func step(by offset: Int, transition: PrototypeTransition = .instant) {
        guard let model, let current, let index = model.viewerBoards.firstIndex(of: current.boardID),
              model.viewerBoards.indices.contains(index + offset) else { return }
        show(model.viewerBoards[index + offset], transition: transition, preserveScroll: false, remember: true)
    }

    /// A board picked from the page's boards: as the pagination goes.
    func go(to boardID: String) {
        guard boardID != current?.boardID else { return }
        show(boardID, transition: .instant, preserveScroll: false, remember: true)
    }

    @objc private func counterTapped() { onShowBoards() }

    private func goToFirstBoard() {
        guard let first = model?.viewerBoards.first, first != current?.boardID else { return }
        show(first, transition: .instant, preserveScroll: false, remember: true)
    }

    // MARK: Taps

    /// A tap at `point`, in the viewport's board coordinates. Open overlays come first,
    /// the top one first: a tap inside runs the overlay's own shapes; outside, one that
    /// closes on a tap outside closes, and one with a background takes the tap
    /// (`viewer-overlay-background`); otherwise the tap goes on down to the board.
    func handleTap(at point: CGPoint, in viewport: BoardViewport) {
        guard viewport === current, !busy, let model else { return }
        if isCommenting {
            guard let board = model.board(viewport.boardID),
                  CGRect(x: 0, y: 0, width: board.selrect.width, height: board.selrect.height).contains(point)
            else { return }
            onPlaceComment(Point(x: point.x + board.selrect.x, y: point.y + board.selrect.y), board.id)
            return
        }
        for overlay in viewport.overlays.reversed() {
            let frame = viewport.displayFrame(of: overlay)
            if frame.contains(point) {
                let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
                if let hit = model.tap(at: local, onBoard: overlay.id) {
                    run(hit, from: overlay, in: viewport)
                } else {
                    viewport.flash(model.hotspots(onBoard: overlay.id).map { $0.offsetBy(dx: frame.minX, dy: frame.minY) })
                }
                return
            }
            if overlay.closesOnTapOutside {
                close(overlay.id, transition: overlay.transition.inverted, in: viewport)
                return
            }
            if overlay.dimsBackground { return }
        }
        let scroll = viewport.scrollOffset
        if let hit = model.tap(at: point, onBoard: viewport.boardID, scroll: scroll) {
            run(hit, from: nil, in: viewport)
        } else {
            viewport.flash(model.hotspots(onBoard: viewport.boardID, scroll: scroll))
        }
    }

    /// Runs what a tap (or a delay) hit, all of the shape's interactions as Penpot does.
    /// `overlay` is the open overlay the shape is in, if any: overlays it opens are placed
    /// from there (`frame-offset`).
    private func run(_ hit: PrototypeModel.Hit, from overlay: BoardViewport.Overlay?, in viewport: BoardViewport) {
        guard let model else { return }
        for interaction in hit.interactions {
            switch PrototypeAction(interaction) {
            case let .navigate(destination, animation, preserveScroll):
                show(destination, transition: PrototypeTransition(animation),
                     preserveScroll: preserveScroll, remember: true)
            case .back:
                // Penpot goes back in the browser's history, without an animation.
                guard !busy, let previous = history.popLast() else { continue }
                show(previous, transition: .instant, preserveScroll: false, remember: false)
            case let .openURL(url):
                onOpenURL(url)
            case let .openOverlay(destination):
                open(destination, for: interaction, from: hit.shapeID, inside: overlay, in: viewport)
            case let .toggleOverlay(destination):
                if viewport.overlay(destination) != nil {
                    close(destination, transition: PrototypeTransition(interaction.animation).inverted, in: viewport)
                } else {
                    open(destination, for: interaction, from: hit.shapeID, inside: overlay, in: viewport)
                }
            case .closeOverlay:
                let open = viewport.overlays.map(\.id)
                if let target = model.closeTarget(for: interaction, from: hit.shapeID, open: open) {
                    close(target, transition: PrototypeTransition(interaction.animation), in: viewport)
                }
            case .none:
                break
            }
        }
    }

    // MARK: Boards

    private func show(_ boardID: String, transition: PrototypeTransition,
                      preserveScroll: Bool, remember: Bool) {
        guard !busy, let model, let board = model.board(boardID) else { return }
        busy = true
        let generation = generation
        Task { [weak self] in
            guard let self else { return }
            // A board with shapes fixed when scrolling is drawn in two layers.
            let fixed = !model.fixedShapes(onBoard: boardID).isEmpty
            var base = fixed ? await self.document(for: Self.layer(board, PenpotSVG.Page.scrollLayerPrefix), awaited: true) : nil
            var fixedLayer = fixed ? await self.document(for: Self.layer(board, PenpotSVG.Page.fixedLayerPrefix), awaited: true) : nil
            if base == nil {
                base = await self.document(for: board, awaited: true)
                fixedLayer = nil
            }
            guard generation == self.generation else { return }
            guard let base else {
                self.busy = false
                self.onRenderFailed()
                return
            }
            let old = self.current
            let viewport = BoardViewport(board: board, document: base, fixedDocument: fixedLayer, stage: self)
            viewport.frame = self.bounds
            viewport.apply(self.zoom, animated: false)
            if preserveScroll, let old { viewport.scroll(toY: old.contentOffset.y) }
            await viewport.prepareLayers()
            guard generation == self.generation else { return }
            if let old { self.cancelDelays(for: old) }
            if remember, let old { self.history.append(old.boardID) }
            self.current = viewport
            self.mirror?.follow(.show(board, base: base, fixed: fixedLayer, transition: transition,
                                      scroll: viewport.scrollFraction))
            self.onBoardChange(boardID)
            self.updateNavigation()
            // The pins wait for the board to arrive.
            self.pinLayer.isHidden = true
            self.updatePins()
            self.animate(from: old, to: viewport, transition) { [weak self] in
                old?.removeFromSuperview()
                guard let self, generation == self.generation else { return }
                self.busy = false
                self.pinLayer.isHidden = false
                self.updatePins()
                self.appeared(boardID, overlay: nil, in: viewport, generation: generation)
            }
        }
    }

    /// The board, or an overlay, appeared: start its delays and render where it leads.
    private func appeared(_ boardID: String, overlay: BoardViewport.Overlay?, in viewport: BoardViewport,
                          generation: Int) {
        guard let model else { return }
        let key = overlay.map { "\(viewport.boardID)/\($0.id)" } ?? viewport.boardID
        for (shapeID, interaction) in model.delayedInteractions(onBoard: boardID) {
            let delay = max(0, interaction.delay ?? 0)
            delayed[key, default: []].append(Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(delay)))
                guard let self, !Task.isCancelled, generation == self.generation,
                      self.current === viewport, !self.busy, !self.isCommenting else { return }
                // An overlay's delay only runs while it is open.
                let open = overlay.flatMap { viewport.overlay($0.id) }
                guard overlay == nil || open != nil else { return }
                self.run(.init(shapeID: shapeID, interactions: [interaction]), from: open, in: viewport)
            })
        }
        // Render where a tap can lead, so the transition starts at once.
        for destination in model.destinations(fromBoard: boardID).prefix(6) {
            guard let board = model.board(destination) else { continue }
            Task { _ = await document(for: board, awaited: false) }
        }
    }

    private func cancelDelays(for viewport: BoardViewport) {
        for key in delayed.keys where key == viewport.boardID || key.hasPrefix(viewport.boardID + "/") {
            delayed[key]?.forEach { $0.cancel() }
            delayed[key] = nil
        }
    }

    private func cancelAllDelays() {
        delayed.values.flatMap { $0 }.forEach { $0.cancel() }
        delayed = [:]
    }

    private static func layer(_ board: Board, _ prefix: String) -> Board {
        Board(id: prefix + board.id, pageID: board.pageID, name: board.name, selrect: board.selrect)
    }

    /// The board's vector render, from memory, or rendered (shared by every caller). A
    /// layer (``PenpotSVG/Page/layer(_:)``) never falls back to Penpot's exporter, which
    /// only knows whole boards.
    private func document(for board: Board, awaited: Bool) async -> CGPDFDocument? {
        if let document = documents[board.id] { return document }
        guard let renders else { return nil }
        if awaited {
            awaitedLoads += 1
            if awaitedLoads == 1 { onLoadingChange(true) }
        }
        defer {
            if awaited {
                awaitedLoads -= 1
                if awaitedLoads == 0 { onLoadingChange(false) }
            }
        }
        let isLayer = PenpotSVG.Page.layer(board.id) != nil
        let task = loads[board.id] ?? Task { await renders.vector(of: board, exporterFallback: !isLayer) }
        loads[board.id] = task
        let document = await task.value
        loads[board.id] = nil
        if let document { documents[board.id] = document }
        return document
    }

    // MARK: Overlays

    private func open(_ destination: String, for interaction: ShapeInteraction, from shapeID: String,
                      inside source: BoardViewport.Overlay?, in viewport: BoardViewport) {
        guard !busy, viewport.overlay(destination) == nil, let model, let board = model.board(destination),
              let frame = model.overlayFrame(for: interaction, from: shapeID, baseBoard: viewport.boardID,
                                             frameOffset: source?.frame.origin ?? .zero,
                                             overlaysOpen: !viewport.overlays.isEmpty) else { return }
        busy = true
        let generation = generation
        Task { [weak self] in
            guard let self else { return }
            let document = await self.document(for: board, awaited: true)
            guard generation == self.generation, self.current === viewport else { return }
            guard let document else {
                self.busy = false
                return
            }
            let overlay = BoardViewport.Overlay(
                id: destination, frame: frame, document: document,
                view: PrototypeLayerView(document: document, size: frame.size),
                closesOnTapOutside: interaction.closeClickOutside ?? false,
                dimsBackground: interaction.backgroundOverlay ?? false,
                transition: PrototypeTransition(interaction.animation),
                isFixed: model.isFixedSource(interaction, from: shapeID) || (source?.isFixed ?? false))
            await overlay.view.prepare(pixelScale: viewport.zoomScale * self.traitCollection.displayScale)
            guard generation == self.generation, self.current === viewport else { return }
            self.mirror?.follow(.openOverlay(overlay))
            viewport.present(overlay) { [weak self] in
                guard let self, generation == self.generation else { return }
                self.busy = false
                self.appeared(destination, overlay: overlay, in: viewport, generation: generation)
            }
        }
    }

    private func close(_ id: String, transition: PrototypeTransition, in viewport: BoardViewport) {
        guard !busy, viewport.overlay(id) != nil else { return }
        busy = true
        let key = "\(viewport.boardID)/\(id)"
        delayed[key]?.forEach { $0.cancel() }
        delayed[key] = nil
        mirror?.follow(.closeOverlay(id, transition: transition))
        viewport.dismiss(id, transition: transition) { [weak self] in
            self?.busy = false
        }
    }

    // MARK: Comments

    /// Shows the pins of the board on screen in comments mode; a pin keeps its view across
    /// reloads.
    private func updatePins() {
        guard isCommenting, let model, let current, let board = model.board(current.boardID) else {
            pinViews.values.forEach { $0.removeFromSuperview() }
            pinViews = [:]
            return
        }
        let shown = threads.filter {
            $0.position != nil && PinMath.thread($0, isOn: board, pageBoardIDs: model.rootBoardIDs)
        }
        let ids = Set(shown.map(\.id))
        for (id, view) in pinViews where !ids.contains(id) {
            view.removeFromSuperview()
            pinViews[id] = nil
        }
        for thread in shown {
            if let view = pinViews[thread.id] {
                view.thread = thread
            } else {
                let view = CommentPinTile(thread: thread) { [weak self] thread in self?.onSelectThread(thread) }
                view.onPickUp = { [weak self] thread in self?.draggedPinID = thread.id }
                view.onDrop = { [weak self] thread, point in self?.drop(thread, at: point) }
                pinLayer.addSubview(view)
                pinViews[thread.id] = view
            }
        }
        positionPins()
    }

    /// Centers each pin on its thread's position on the board, as the board now shows.
    private func positionPins() {
        guard let model, let current, let board = model.board(current.boardID) else { return }
        for view in pinViews.values where view.thread.id != draggedPinID {
            guard let position = view.thread.position else { continue }
            let point = CGPoint(x: position.x - board.selrect.x, y: position.y - board.selrect.y)
            view.center = current.convert(boardPoint: point, to: pinLayer)
        }
    }

    /// The board scrolled or zoomed.
    func viewportDidMove(_ viewport: BoardViewport) {
        guard viewport === current else { return }
        positionPins()
        mirror?.followScroll(viewport.scrollFraction)
    }

    /// A pin let go at `point` (pin layer coordinates), or `nil` when the drag was
    /// cancelled: on the board it moves there, else it goes back.
    private func drop(_ thread: CommentThread, at point: CGPoint?) {
        draggedPinID = nil
        guard let point, let model, let current, let board = model.board(current.boardID) else {
            positionPins()
            return
        }
        let local = current.convert(point, toBoardFrom: pinLayer)
        guard CGRect(x: 0, y: 0, width: board.selrect.width, height: board.selrect.height).contains(local) else {
            positionPins()
            return
        }
        onMoveThread(thread, Point(x: local.x + board.selrect.x, y: local.y + board.selrect.y), board.id)
    }

    // MARK: Mirror

    /// What a stage shows, for its ``mirror`` to show too.
    enum MirrorEvent {
        /// A board, drawn from these documents, coming in with `transition` and scrolled
        /// to `scroll` (0 is the top, 1 the bottom).
        case show(Board, base: CGPDFDocument, fixed: CGPDFDocument?, transition: PrototypeTransition, scroll: CGFloat)
        case openOverlay(BoardViewport.Overlay)
        case closeOverlay(String, transition: PrototypeTransition)
    }

    private var mirrorQueue: [MirrorEvent] = []
    private var isFollowing = false

    /// Hands the mirror what is on screen now, at once: it came in mid-presentation.
    private func syncMirror() {
        guard let mirror else { return }
        mirror.zoom = zoom
        guard let current, !busy else { return }
        mirror.follow(.show(current.board, base: current.document, fixed: current.fixedDocument,
                            transition: .instant, scroll: current.scrollFraction))
        for overlay in current.overlays {
            mirror.follow(.openOverlay(overlay.withTransition(.instant)))
        }
    }

    /// Shows what the presenting stage showed, one change after another. A new board
    /// replaces whatever was still waiting: those changes belonged to boards it leaves.
    func follow(_ event: MirrorEvent) {
        if case .show = event { mirrorQueue.removeAll() }
        mirrorQueue.append(event)
        drainMirrorQueue()
    }

    /// The presenting stage's board scrolled.
    func followScroll(_ fraction: CGFloat) {
        guard !isFollowing else { return }
        current?.scroll(toFraction: fraction)
    }

    private func drainMirrorQueue() {
        guard !isFollowing, !mirrorQueue.isEmpty else { return }
        isFollowing = true
        let event = mirrorQueue.removeFirst()
        Task { [weak self] in
            await self?.apply(event)
            self?.isFollowing = false
            self?.drainMirrorQueue()
        }
    }

    private func apply(_ event: MirrorEvent) async {
        switch event {
        case let .show(board, base, fixed, transition, scroll):
            let old = current
            let viewport = BoardViewport(board: board, document: base, fixedDocument: fixed, stage: self)
            viewport.frame = bounds
            viewport.apply(zoom, animated: false)
            viewport.scroll(toFraction: scroll)
            await viewport.prepareLayers()
            current = viewport
            await withCheckedContinuation { continuation in
                animate(from: old, to: viewport, transition) {
                    old?.removeFromSuperview()
                    continuation.resume()
                }
            }
        case let .openOverlay(source):
            guard let current, current.overlay(source.id) == nil else { return }
            let overlay = source.withView(PrototypeLayerView(document: source.document, size: source.frame.size))
            await overlay.view.prepare(pixelScale: current.zoomScale * traitCollection.displayScale)
            guard current === self.current else { return }
            await withCheckedContinuation { continuation in
                current.present(overlay) { continuation.resume() }
            }
        case let .closeOverlay(id, transition):
            guard let current else { return }
            await withCheckedContinuation { continuation in
                current.dismiss(id, transition: transition) { continuation.resume() }
            }
        }
    }

    // MARK: Transitions

    private func animate(from old: BoardViewport?, to new: BoardViewport,
                         _ transition: PrototypeTransition, completion: @escaping () -> Void) {
        guard let old, transition.kind != .none, transition.duration > 0,
              !UIAccessibility.isReduceMotionEnabled else {
            addSubview(new)
            completion()
            return
        }
        let motion = transition.motion
        if motion.oldOnTop { insertSubview(new, belowSubview: old) } else { addSubview(new) }
        let size = bounds.size
        func offset(_ v: CGVector) -> CGAffineTransform {
            CGAffineTransform(translationX: v.dx * size.width, y: v.dy * size.height)
        }
        new.transform = offset(motion.newFrom)
        new.alpha = motion.newAlphaFrom
        old.transform = offset(motion.oldFrom)
        let timing = transition.timing
        let finish = {
            old.transform = .identity
            old.alpha = 1
            completion()
        }
        if transition.kind == .dissolve {
            // Penpot's three keyframes: the new board is fully there halfway through, and
            // only then (a third to two thirds in) does the old one fade, so the background
            // never shows between them.
            let fadeIn = UIViewPropertyAnimator(duration: transition.duration / 2, timingParameters: timing)
            fadeIn.addAnimations { new.alpha = 1 }
            let fadeOut = UIViewPropertyAnimator(duration: transition.duration / 3, timingParameters: timing)
            fadeOut.addAnimations { old.alpha = 0 }
            fadeOut.addCompletion { _ in finish() }
            fadeIn.startAnimation()
            fadeOut.startAnimation(afterDelay: transition.duration / 3)
        } else {
            let animator = UIViewPropertyAnimator(duration: transition.duration, timingParameters: timing)
            animator.addAnimations {
                new.transform = .identity
                new.alpha = 1
                old.transform = offset(motion.oldTo)
                old.alpha = motion.oldAlphaTo
            }
            animator.addCompletion { _ in finish() }
            animator.startAnimation()
        }
    }
}

extension PrototypeTransition {
    /// The easing as UIKit timing.
    var timing: UICubicTimingParameters {
        UICubicTimingParameters(controlPoint1: controlPoints.0, controlPoint2: controlPoints.1)
    }

    /// Whether it animates at all here.
    var animates: Bool { kind != .none && duration > 0 && !UIAccessibility.isReduceMotionEnabled }
}

/// A vector render drawn through a tiled layer, over a bitmap of itself: Core Animation
/// draws a tiled layer's tiles only once it is on screen, a tile at a time, so a board
/// moving in would show gaps until they arrive. The sharp tiles fade in over the bitmap.
@MainActor
final class PrototypeLayerView: UIView {
    private let placeholder = UIImageView()
    private let page = BoardVectorView.PageView()

    init(document: CGPDFDocument, size: CGSize) {
        super.init(frame: CGRect(origin: .zero, size: size))
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for view in [placeholder, page] as [UIView] {
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
        }
        page.pageLayer.page = document.page(at: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Draws the bitmap at `pixelScale` pixels per design unit, at most 4096 px a side
    /// (a long board gets a coarser one; the tiles are sharp anyway).
    func prepare(pixelScale: CGFloat) async {
        guard let pdfPage = page.pageLayer.page else { return }
        let size = bounds.size
        let scale = min(max(pixelScale, 1), 4096 / max(size.width, size.height, 1))
        placeholder.image = await Task.detached(priority: .userInitiated) {
            Self.bitmap(of: pdfPage, size: size, scale: scale)
        }.value
    }

    private nonisolated static func bitmap(of page: CGPDFPage, size: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext
            let box = page.getBoxRect(.mediaBox)
            guard box.width > 0, box.height > 0 else { return }
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: size.width / box.width, y: -size.height / box.height)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.drawPDFPage(page)
        }
    }
}

/// One board on the stage: its vector render in a scroll view that zooms (Penpot's fit,
/// fill and 100 %, plus pinching) and scrolls where the board is longer than the screen.
/// Shapes fixed when scrolling are a layer of their own that keeps its place on screen;
/// open overlays sit above everything, in the board's coordinates.
@MainActor
final class BoardViewport: UIScrollView, UIScrollViewDelegate {
    /// An open overlay (`viewer-overlays`).
    struct Overlay {
        let id: String
        /// Where it opened, in the board's coordinates; one placed against a fixed shape
        /// keeps its place on screen like that shape (`fixed-source?`).
        let frame: CGRect
        /// Its render, for a mirroring stage to draw too.
        let document: CGPDFDocument
        let view: PrototypeLayerView
        let closesOnTapOutside: Bool
        let dimsBackground: Bool
        /// How it opened; closing by a tap outside plays it backwards.
        let transition: PrototypeTransition
        let isFixed: Bool

        func withView(_ view: PrototypeLayerView) -> Overlay {
            Overlay(id: id, frame: frame, document: document, view: view, closesOnTapOutside: closesOnTapOutside,
                    dimsBackground: dimsBackground, transition: transition, isFixed: isFixed)
        }

        func withTransition(_ transition: PrototypeTransition) -> Overlay {
            Overlay(id: id, frame: frame, document: document, view: view, closesOnTapOutside: closesOnTapOutside,
                    dimsBackground: dimsBackground, transition: transition, isFixed: isFixed)
        }
    }

    let boardID: String
    let board: Board
    /// The renders it shows, for a mirroring stage.
    let document: CGPDFDocument
    let fixedDocument: CGPDFDocument?
    private let boardSize: CGSize
    private let content = UIView()
    private let base: PrototypeLayerView
    private let fixed: PrototypeLayerView?
    private let overlayLayer = UIView()
    private let hints = UIView()
    private(set) var overlays: [Overlay] = []
    private var dims: [String: UIView] = [:]
    private weak var stage: PrototypeStageView?
    private var mode: PrototypeZoom = .fit
    private var appliedSize: CGSize = .zero

    init(board: Board, document: CGPDFDocument, fixedDocument: CGPDFDocument?, stage: PrototypeStageView) {
        boardID = board.id
        self.board = board
        self.document = document
        self.fixedDocument = fixedDocument
        let size = CGSize(width: board.selrect.width, height: board.selrect.height)
        boardSize = size
        base = PrototypeLayerView(document: document, size: size)
        fixed = fixedDocument.map { PrototypeLayerView(document: $0, size: size) }
        self.stage = stage
        super.init(frame: .zero)
        delegate = self
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        backgroundColor = .clear
        content.frame = CGRect(origin: .zero, size: boardSize)
        for view in [base, fixed, overlayLayer, hints].compactMap({ $0 }) as [UIView] {
            content.addSubview(view)
        }
        overlayLayer.frame = content.bounds
        overlayLayer.isUserInteractionEnabled = false
        hints.frame = content.bounds
        hints.isUserInteractionEnabled = false
        addSubview(content)
        contentSize = boardSize
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        isAccessibilityElement = true
        accessibilityLabel = board.name
        accessibilityTraits = .image
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        pinFixedContent()
        stage?.viewportDidMove(self)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        pinFixedContent()
        stage?.viewportDidMove(self)
    }

    /// A point on the board (its own units) in `view`'s coordinates.
    func convert(boardPoint point: CGPoint, to view: UIView) -> CGPoint {
        content.convert(point, to: view)
    }

    /// A point in `view` on the board, in its own units.
    func convert(_ point: CGPoint, toBoardFrom view: UIView) -> CGPoint {
        view.convert(point, to: content)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A new size (rotation, full screen) keeps the chosen zoom style, as Penpot refits.
        if bounds.size != appliedSize, bounds.width > 0, bounds.height > 0 {
            apply(mode, animated: false)
        }
    }

    func apply(_ mode: PrototypeZoom, animated: Bool) {
        self.mode = mode
        guard bounds.width > 0, bounds.height > 0 else { return }
        appliedSize = bounds.size
        let scale = mode.scale(board: boardSize, viewport: bounds.size)
        let fit = PrototypeZoom.fit.scale(board: boardSize, viewport: bounds.size)
        minimumZoomScale = min(fit, scale)
        // The page layer draws up to 8× its size sharply (`levelsOfDetailBias`).
        maximumZoomScale = max(scale, 8)
        setZoomScale(scale, animated: animated)
        centerContent()
        if !animated { scroll(toY: -contentInset.top) }
        pinFixedContent()
    }

    /// Scrolls to `y`, kept inside the board; horizontally the board stays centred.
    func scroll(toY y: CGFloat) {
        let maxY = max(-contentInset.top, contentSize.height - bounds.height + contentInset.bottom)
        let x = contentSize.width > bounds.width ? (contentSize.width - bounds.width) / 2 : -contentInset.left
        contentOffset = CGPoint(x: x, y: min(max(y, -contentInset.top), maxY))
    }

    /// How far down the board has scrolled, 0 at the top and 1 at the bottom: what a
    /// mirroring stage of another size scrolls to.
    var scrollFraction: CGFloat {
        let range = contentSize.height - bounds.height + contentInset.top + contentInset.bottom
        guard range > 1 else { return 0 }
        return min(max((contentOffset.y + contentInset.top) / range, 0), 1)
    }

    func scroll(toFraction fraction: CGFloat) {
        let range = contentSize.height - bounds.height + contentInset.top + contentInset.bottom
        guard range > 1 else { return }
        scroll(toY: fraction * range - contentInset.top)
    }

    private func centerContent() {
        let x = max(0, (bounds.width - contentSize.width) / 2)
        let y = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    /// The screen, in the board's coordinates.
    var visibleRect: CGRect { convert(bounds, to: content) }

    /// How far the board has scrolled, in its own units: what fixed content moves by to
    /// stay in place.
    var scrollOffset: CGPoint {
        let visible = visibleRect
        return CGPoint(x: max(0, visible.minX), y: max(0, visible.minY))
    }

    private func pinFixedContent() {
        let offset = scrollOffset
        fixed?.frame.origin = offset
        for overlay in overlays where overlay.isFixed {
            overlay.view.frame.origin = CGPoint(x: overlay.frame.minX + offset.x, y: overlay.frame.minY + offset.y)
        }
    }

    /// Draws the layers' bitmaps at the size they show, before the board appears.
    func prepareLayers() async {
        let pixelScale = zoomScale * (stage?.traitCollection.displayScale ?? 3)
        await base.prepare(pixelScale: pixelScale)
        await fixed?.prepare(pixelScale: pixelScale)
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        stage?.handleTap(at: recognizer.location(in: content), in: self)
    }

    // MARK: Overlays

    func overlay(_ id: String) -> Overlay? { overlays.first { $0.id == id } }

    /// Where the overlay shows now, in the board's coordinates.
    func displayFrame(of overlay: Overlay) -> CGRect {
        guard overlay.isFixed else { return overlay.frame }
        let offset = scrollOffset
        return overlay.frame.offsetBy(dx: offset.x, dy: offset.y)
    }

    func present(_ overlay: Overlay, completion: @escaping () -> Void) {
        overlays.append(overlay)
        if overlay.dimsBackground || overlay.closesOnTapOutside {
            // Penpot's `viewer-overlay-background` covers the whole screen, 20 % black
            // when the overlay dims.
            let dim = UIView(frame: content.bounds.insetBy(dx: -20_000, dy: -20_000))
            dim.backgroundColor = overlay.dimsBackground ? UIColor.black.withAlphaComponent(0.2) : .clear
            dim.isUserInteractionEnabled = false
            overlayLayer.addSubview(dim)
            dims[overlay.id] = dim
        }
        overlayLayer.addSubview(overlay.view)
        let frame = displayFrame(of: overlay)
        let transition = overlay.transition
        guard transition.animates else {
            overlay.view.frame = frame
            completion()
            return
        }
        let start = transition.overlayStart(frame, visible: visibleRect)
        overlay.view.frame = CGRect(origin: start.origin, size: frame.size)
        overlay.view.alpha = start.alpha
        let animator = UIViewPropertyAnimator(duration: transition.duration, timingParameters: transition.timing)
        animator.addAnimations {
            overlay.view.frame = frame
            overlay.view.alpha = 1
        }
        animator.addCompletion { _ in completion() }
        animator.startAnimation()
    }

    func dismiss(_ id: String, transition: PrototypeTransition, completion: @escaping () -> Void) {
        guard let overlay = overlay(id) else {
            completion()
            return
        }
        let remove = { [weak self] in
            overlay.view.removeFromSuperview()
            self?.dims[id]?.removeFromSuperview()
            self?.dims[id] = nil
            self?.overlays.removeAll { $0.id == id }
            completion()
        }
        guard transition.animates else {
            remove()
            return
        }
        let frame = displayFrame(of: overlay)
        let end = transition.overlayEnd(frame, visible: visibleRect)
        let animator = UIViewPropertyAnimator(duration: transition.duration, timingParameters: transition.timing)
        animator.addAnimations {
            overlay.view.frame.origin = end.origin
            overlay.view.alpha = end.alpha
        }
        animator.addCompletion { _ in remove() }
        animator.startAnimation()
    }

    // MARK: Hints

    /// Shows where a tap does something, briefly (Penpot's "show on click").
    func flash(_ rects: [CGRect]) {
        hints.subviews.forEach { $0.removeFromSuperview() }
        guard !rects.isEmpty else { return }
        content.bringSubviewToFront(hints)
        for rect in rects {
            let hint = UIView(frame: rect.insetBy(dx: -1, dy: -1))
            hint.backgroundColor = UIColor.penpotAccent.withAlphaComponent(0.25)
            hint.layer.borderColor = UIColor.penpotAccent.cgColor
            hint.layer.borderWidth = 1 / max(zoomScale, 0.01)
            hint.layer.cornerRadius = 2
            hints.addSubview(hint)
        }
        hints.alpha = 0
        UIView.animate(withDuration: 0.15) { self.hints.alpha = 1 } completion: { _ in
            UIView.animate(withDuration: 0.35, delay: 0.6) { self.hints.alpha = 0 }
        }
    }
}

extension PrototypeStageView: UIGestureRecognizerDelegate {
    /// The two-finger hold that ends full screen and the swipes run alongside the boards'
    /// own scrolling, zooming and taps.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// A label with room around its text: the board counter and the full-screen hint.
private final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let inner = CGSize(width: size.width - insets.left - insets.right,
                           height: size.height - insets.top - insets.bottom)
        let fit = super.sizeThatFits(inner)
        return CGSize(width: fit.width + insets.left + insets.right,
                      height: fit.height + insets.top + insets.bottom)
    }
}
