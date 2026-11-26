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

    /// Full screen's close button. It lives here, in UIKit: as a SwiftUI overlay over this
    /// view it never got its taps, which went to the board under it. It sits over the
    /// design, so it shows for a few seconds when full screen starts and then goes away
    /// entirely; touching and holding the prototype for five seconds brings it back. With
    /// VoiceOver it stays, as a five-second hold is no gesture there.
    var showsExitButton = false {
        didSet {
            guard showsExitButton != oldValue else { return }
            revealHold.isEnabled = showsExitButton
            if showsExitButton {
                revealExitButton(for: 3)
            } else {
                hideExitTask?.cancel()
                exitButton.layer.removeAllAnimations()
                exitButton.isHidden = true
            }
        }
    }

    private var exitButton: UIButton!
    private var hideExitTask: Task<Void, Never>?
    private lazy var revealHold: UILongPressGestureRecognizer = {
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(heldForExitButton(_:)))
        hold.minimumPressDuration = 5
        hold.cancelsTouchesInView = false
        hold.delegate = self
        hold.isEnabled = false
        return hold
    }()

    private func revealExitButton(for seconds: Double) {
        hideExitTask?.cancel()
        exitButton.layer.removeAllAnimations()
        if exitButton.isHidden {
            exitButton.alpha = 0
            exitButton.isHidden = false
        }
        bringSubviewToFront(exitButton)
        UIView.animate(withDuration: 0.2) { self.exitButton.alpha = 1 }
        guard !UIAccessibility.isVoiceOverRunning else { return }
        hideExitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.showsExitButton else { return }
            UIView.animate(withDuration: 0.4) {
                self.exitButton.alpha = 0
            } completion: { finished in
                if finished, self.showsExitButton { self.exitButton.isHidden = true }
            }
        }
    }

    @objc private func heldForExitButton(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, showsExitButton else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        revealExitButton(for: 4)
    }

    private func makeExitButton() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = Self.icon(AppIcon.closeFilled.assetName, size: 18)
        configuration.baseForegroundColor = .label
        configuration.background.visualEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        configuration.background.cornerRadius = 22
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.onExitFullScreen()
        })
        button.accessibilityLabel = .appLocalized("Full screen")
        button.accessibilityTraits.insert(.selected)
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
        didSet { if zoom != oldValue { current?.apply(zoom, animated: true) } }
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
        exitButton = makeExitButton()
        addSubview(exitButton)
        addGestureRecognizer(revealHold)
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

    override func layoutSubviews() {
        super.layoutSubviews()
        // Not `frame`: during a transition the viewports carry a transform, and setting the
        // frame then moves their centre to undo it. A scroll view's `bounds.origin` is its
        // scroll position, so only the size is set.
        for case let viewport as BoardViewport in subviews {
            viewport.center = CGPoint(x: bounds.midX, y: bounds.midY)
            if viewport.bounds.size != bounds.size { viewport.bounds.size = bounds.size }
        }
        exitButton.frame = CGRect(x: bounds.maxX - safeAreaInsets.right - 12 - 44,
                                  y: safeAreaInsets.top + 8, width: 44, height: 44)
        bringSubviewToFront(exitButton)
    }

    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        // A board added for a transition must not cover the close button.
        if let exitButton, subview !== exitButton, !exitButton.isHidden { bringSubviewToFront(exitButton) }
    }

    // MARK: Taps

    /// A tap at `point`, in the viewport's board coordinates. Open overlays come first,
    /// the top one first: a tap inside runs the overlay's own shapes; outside, one that
    /// closes on a tap outside closes, and one with a background takes the tap
    /// (`viewer-overlay-background`); otherwise the tap goes on down to the board.
    func handleTap(at point: CGPoint, in viewport: BoardViewport) {
        guard viewport === current, !busy, let model else { return }
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
            self.onBoardChange(boardID)
            self.animate(from: old, to: viewport, transition) { [weak self] in
                old?.removeFromSuperview()
                guard let self, generation == self.generation else { return }
                self.busy = false
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
                      self.current === viewport, !self.busy else { return }
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
                id: destination, frame: frame,
                view: PrototypeLayerView(document: document, size: frame.size),
                closesOnTapOutside: interaction.closeClickOutside ?? false,
                dimsBackground: interaction.backgroundOverlay ?? false,
                transition: PrototypeTransition(interaction.animation),
                isFixed: model.isFixedSource(interaction, from: shapeID) || (source?.isFixed ?? false))
            await overlay.view.prepare(pixelScale: viewport.zoomScale * self.traitCollection.displayScale)
            guard generation == self.generation, self.current === viewport else { return }
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
        viewport.dismiss(id, transition: transition) { [weak self] in
            self?.busy = false
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
        let view: PrototypeLayerView
        let closesOnTapOutside: Bool
        let dimsBackground: Bool
        /// How it opened; closing by a tap outside plays it backwards.
        let transition: PrototypeTransition
        let isFixed: Bool
    }

    let boardID: String
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
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { pinFixedContent() }

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
    /// The five-second hold that brings back full screen's close button runs alongside
    /// the boards' own scrolling, zooming and taps.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
