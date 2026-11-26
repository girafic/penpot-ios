import CoreGraphics
import Foundation

/// A page's prototype as the native player (``PrototypePlayerView``) plays it: what a tap
/// on a board runs, what runs on its own after a delay, where overlays open, what stays put
/// while a board scrolls, and where the flows start. It follows Penpot's viewer
/// (`ui/viewer/shapes.cljs`, `data/viewer.cljs`, `types/shape/interactions.cljc`):
/// - A click or mouse-press runs on the front-most shape under the pointer that has one.
///   Penpot stops the event there (`dom/stop-propagation`): the DOM target is the painted
///   shape on top, and the first of it and its ancestors with such an interaction takes
///   the event. Groups paint nothing of their own; a board only where it has a fill.
/// - Hover events (`mouse-enter`, `mouse-over`, `mouse-leave`) have no touch equivalent.
/// - `after-delay` interactions run that long after their board appears (`on-load`).
/// - Shapes fixed when scrolling (`fixed-scroll?`) sit in a layer above the board that
///   doesn't scroll, so they take taps first, where they show.
///
/// Geometry is the stored `selrect`, in page coordinates; the player works in a board's
/// own coordinates, its top-left corner at the origin.
struct PrototypeModel {
    let pageID: String
    let page: PenpotPage
    /// The page's flows, by name, as Penpot's flow menu lists them.
    let flows: [PrototypeFlow]

    /// What a tap hit: the shape whose interactions run (an overlay is placed against it).
    struct Hit: Equatable {
        let shapeID: String
        let interactions: [ShapeInteraction]
    }

    init(pageID: String, page: PenpotPage) {
        self.pageID = pageID
        self.page = page
        let flows = page.flows?.flows ?? page.options?.flows?.flows ?? []
        self.flows = flows
            .filter { $0.startingFrame.map { page.objects[$0] != nil } ?? false }
            .sorted { ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending }
    }

    private var objects: [String: Shape] { page.objects }

    /// A board (a root or a nested frame) as the renderer draws it.
    func board(_ id: String) -> Board? {
        guard let shape = objects[id], shape.type == "frame",
              let rect = shape.selrect, rect.width > 0, rect.height > 0 else { return nil }
        return Board(id: id, pageID: pageID, name: shape.name ?? "", selrect: rect)
    }

    /// Where playing starts: `preferred` when it is a board of this page (the board the
    /// user played from), else the first flow's start, else the viewer's first board.
    func startBoard(preferred: String?) -> String? {
        if let preferred, board(preferred) != nil { return preferred }
        if let start = flows.lazy.compactMap(\.startingFrame).first(where: { board($0) != nil }) {
            return start
        }
        return page.viewerFrameIDs.first { board($0) != nil }
    }

    // MARK: Taps

    /// What a tap at `point` on the board runs, or nil when it hits nothing that runs (the
    /// player then flashes the hotspots, as Penpot's "show on click" does). `scroll` is how
    /// far the board has scrolled, in its own units: fixed shapes sit that much further.
    func tap(at point: CGPoint, onBoard boardID: String, scroll: CGPoint = .zero) -> Hit? {
        guard let board = board(boardID), contains(board, point) else { return nil }
        let fixed = fixedSubtree(onBoard: boardID)
        let fixedPoint = CGPoint(x: point.x - scroll.x, y: point.y - scroll.y)
        let order = frontToBack(board: boardID)
        let hit = order.first { fixed.contains($0) && (rect(of: $0, in: board)?.contains(fixedPoint) ?? false) }
            ?? order.first { !fixed.contains($0) && (rect(of: $0, in: board)?.contains(point) ?? false) }
        var cursor = hit ?? boardID
        while true {
            let interactions = Self.tapInteractions(of: objects[cursor])
            if !interactions.isEmpty { return Hit(shapeID: cursor, interactions: interactions) }
            guard cursor != boardID,
                  let parent = objects[cursor]?.parentId, parent != Board.rootFrameID else { return nil }
            cursor = parent
        }
    }

    /// The areas a tap runs something on, in the board's coordinates; fixed ones moved by
    /// `scroll`, as they show.
    func hotspots(onBoard boardID: String, scroll: CGPoint = .zero) -> [CGRect] {
        guard let board = board(boardID) else { return [] }
        let fixed = fixedSubtree(onBoard: boardID)
        return ([boardID] + subtree(of: boardID))
            .filter { !Self.tapInteractions(of: objects[$0]).isEmpty }
            .compactMap { id in
                guard let rect = rect(of: id, in: board) else { return nil }
                return fixed.contains(id) ? rect.offsetBy(dx: scroll.x, dy: scroll.y) : rect
            }
    }

    /// The `after-delay` interactions of the board and its shapes.
    func delayedInteractions(onBoard boardID: String) -> [(shapeID: String, interaction: ShapeInteraction)] {
        ([boardID] + subtree(of: boardID)).flatMap { id in
            (objects[id]?.interactions ?? [])
                .filter { $0.eventType == "after-delay" }
                .map { (shapeID: id, interaction: $0) }
        }
    }

    /// The boards this board's interactions lead to (navigations and overlays), to render
    /// them ahead.
    func destinations(fromBoard boardID: String) -> [String] {
        var seen: Set<String> = []
        return ([boardID] + subtree(of: boardID))
            .flatMap { objects[$0]?.interactions ?? [] }
            .compactMap { ["navigate", "open-overlay", "toggle-overlay"].contains($0.actionType ?? "") ? $0.destination : nil }
            .filter { board($0) != nil && seen.insert($0).inserted }
    }

    /// Click and mouse-press, Penpot's default event being click.
    static func tapInteractions(of shape: Shape?) -> [ShapeInteraction] {
        (shape?.interactions ?? []).filter {
            let event = $0.eventType ?? "click"
            return event == "click" || event == "mouse-press"
        }
    }

    // MARK: Fixed when scrolling

    /// The board's shapes fixed when scrolling, the outermost ones: Penpot's
    /// `fixed-scroll?` takes a shape with `fixedScroll` that is a frame's direct child (not
    /// inside a group), the frame not being the page's root.
    func fixedShapes(onBoard boardID: String) -> [String] {
        var result: [String] = []
        var stack = objects[boardID]?.shapes ?? []
        var visited: Set<String> = [boardID]
        while let id = stack.popLast() {
            guard visited.insert(id).inserted, let shape = objects[id], shape.hidden != true else { continue }
            if Self.isFixedScroll(shape) {
                result.append(id)   // its subtree goes with it
            } else {
                stack += shape.shapes ?? []
            }
        }
        return result.sorted()
    }

    static func isFixedScroll(_ shape: Shape) -> Bool {
        shape.fixedScroll == true && shape.parentId != nil && shape.parentId == shape.frameId
            && shape.frameId != Board.rootFrameID
    }

    private func fixedSubtree(onBoard boardID: String) -> Set<String> {
        let roots = fixedShapes(onBoard: boardID)
        return Set(roots + roots.flatMap(subtree(of:)))
    }

    // MARK: Overlays

    /// Where an overlay opens, in the coordinates of the board being played (`baseBoard`,
    /// its top-left at the origin): Penpot's `calc-overlay-position`. `frameOffset` is the
    /// position of the overlay the tapped shape is in, if any.
    func overlayFrame(for interaction: ShapeInteraction, from shapeID: String, baseBoard: String,
                      frameOffset: CGPoint = .zero, overlaysOpen: Bool = false) -> CGRect? {
        guard let destinationID = interaction.destination,
              let destination = objects[destinationID]?.selrect,
              let base = objects[baseBoard], let baseRect = base.selrect else { return nil }
        let manual = interaction.overlayPosType == "manual"
        let shape = objects[shapeID]
        // Penpot ignores that the source is a board unless the position is manual
        // (`ignore-frame-shape`).
        let shapeIsFrame = shape?.type == "frame" && (manual || shape?.frameId == nil)
        let relativeID: String? = manual ? (shapeIsFrame ? shape?.frameId : shapeID) : interaction.positionRelativeTo
        let relative = relativeID.flatMap { objects[$0] } ?? base
        let relativeIsFrame = relativeID == shapeID ? shapeIsFrame : relative.type == "frame"
        guard let relativeRect = relative.selrect else { return nil }

        // The frame the relative shape is measured from (`find-relative-to-base-frame`).
        var reference = base
        if relativeIsFrame {
            reference = relative
        } else if overlaysOpen, let start = relativeID {
            var cursor = objects[start]?.parentId
            while let id = cursor, id != Board.rootFrameID, let parent = objects[id] {
                if parent.type == "frame" { reference = parent; break }
                cursor = parent.parentId
            }
        }
        let referenceOrigin = reference.selrect.map { CGPoint(x: $0.x, y: $0.y) } ?? CGPoint(x: baseRect.x, y: baseRect.y)
        let adjusted = CGPoint(x: relativeRect.x - referenceOrigin.x, y: relativeRect.y - referenceOrigin.y)

        // A manual position from inside a nested board counts from that board.
        var offset = frameOffset
        let shapeFrame = shapeIsFrame ? shape : shape?.frameId.flatMap { objects[$0] }
        if manual, let frame = shapeFrame, let frameRect = frame.selrect,
           frame.id != Board.rootFrameID, frame.parentId != Board.rootFrameID, frame.id != baseBoard {
            offset.x += frameRect.x - baseRect.x
            offset.y += frameRect.y - baseRect.y
        }

        let automatic = interaction.positionRelativeTo == nil && !manual
        let origin = automatic ? CGPoint.zero : CGPoint(x: offset.x + adjusted.x, y: offset.y + adjusted.y)
        let size = CGSize(width: relativeRect.width, height: relativeRect.height)
        let overlay = CGSize(width: destination.width, height: destination.height)
        let point: CGPoint
        switch interaction.overlayPosType ?? "center" {
        case "manual":
            let given = interaction.overlayPosition.map { CGPoint(x: $0.x, y: $0.y) } ?? .zero
            let position = relativeIsFrame ? given : CGPoint(x: given.x - adjusted.x, y: given.y - adjusted.y)
            point = CGPoint(x: origin.x + position.x, y: origin.y + position.y)
        case "top-left":
            point = origin
        case "top-right":
            point = CGPoint(x: origin.x + size.width - overlay.width, y: origin.y)
        case "top-center":
            point = CGPoint(x: origin.x + (size.width - overlay.width) / 2, y: origin.y)
        case "bottom-left":
            point = CGPoint(x: origin.x, y: origin.y + size.height - overlay.height)
        case "bottom-right":
            point = CGPoint(x: origin.x + size.width - overlay.width, y: origin.y + size.height - overlay.height)
        case "bottom-center":
            point = CGPoint(x: origin.x + (size.width - overlay.width) / 2, y: origin.y + size.height - overlay.height)
        default:   // center
            point = CGPoint(x: origin.x + (size.width - overlay.width) / 2,
                            y: origin.y + (size.height - overlay.height) / 2)
        }
        return CGRect(origin: point, size: overlay)
    }

    /// The overlay a `close-overlay` closes: its destination, else the open overlay the
    /// tapped shape is in (Penpot: the shape itself when it is an open overlay's board,
    /// else its frame).
    func closeTarget(for interaction: ShapeInteraction, from shapeID: String, open: [String]) -> String? {
        if let destination = interaction.destination { return destination }
        var cursor: String? = shapeID
        while let id = cursor, id != Board.rootFrameID {
            if open.contains(id) { return id }
            cursor = objects[id]?.parentId
        }
        return objects[shapeID]?.frameId
    }

    /// Whether the overlay's position is fixed while the board scrolls: it is placed
    /// against a fixed shape (Penpot's `fixed?`).
    func isFixedSource(_ interaction: ShapeInteraction, from shapeID: String) -> Bool {
        let shape = objects[shapeID]
        let relativeID = interaction.overlayPosType == "manual"
            ? (shape?.type == "frame" ? shape?.frameId : shapeID)
            : interaction.positionRelativeTo
        guard let id = relativeID, let relative = objects[id] else { return false }
        // The shape, what it holds, and what holds it up to (not including) its root board.
        var ids = [id] + subtree(of: id)
        var cursor = relative.parentId
        while let parentID = cursor, parentID != Board.rootFrameID, let parent = objects[parentID],
              !(parent.type == "frame" && parent.parentId == Board.rootFrameID) {
            ids.append(parentID)
            cursor = parent.parentId
        }
        return ids.contains { objects[$0].map(Self.isFixedScroll) ?? false }
    }

    // MARK: Geometry

    private func contains(_ board: Board, _ point: CGPoint) -> Bool {
        CGRect(x: 0, y: 0, width: board.selrect.width, height: board.selrect.height).contains(point)
    }

    private func rect(of id: String, in board: Board) -> CGRect? {
        guard let r = objects[id]?.selrect else { return nil }
        return CGRect(x: r.x - board.selrect.x, y: r.y - board.selrect.y, width: r.width, height: r.height)
    }

    /// The board's visible shapes that paint something a tap can land on, the front-most
    /// first: a shape's children paint over it, so they come before it.
    func frontToBack(board boardID: String) -> [String] {
        guard let board = objects[boardID] else { return [] }
        var order: [String] = []
        var visited: Set<String> = [boardID]
        func visit(_ parent: Shape) {
            for id in page.viewerOrder(ofChildrenOf: parent) where visited.insert(id).inserted {
                guard let shape = objects[id], shape.hidden != true else { continue }
                visit(shape)
                if Self.paintsHitArea(shape) { order.append(id) }
            }
        }
        visit(board)
        return order
    }

    /// Groups draw nothing of their own, and a board without a fill lets the pointer
    /// through.
    private static func paintsHitArea(_ shape: Shape) -> Bool {
        switch shape.type {
        case "group": false
        case "frame": shape.hasFills
        default: true
        }
    }

    /// The shape's visible descendants, in no particular order.
    private func subtree(of id: String) -> [String] {
        var result: [String] = []
        var stack = objects[id]?.shapes ?? []
        var visited: Set<String> = [id]
        while let next = stack.popLast() {
            guard visited.insert(next).inserted, let shape = objects[next], shape.hidden != true else { continue }
            result.append(next)
            stack += shape.shapes ?? []
        }
        return result
    }
}

/// What an interaction does, as the player plays it.
enum PrototypeAction: Equatable {
    case navigate(to: String, animation: PrototypeAnimation?, preserveScroll: Bool)
    case back
    case openURL(URL)
    case openOverlay(String)
    case toggleOverlay(String)
    /// Which overlay closes depends on where the tap was (``PrototypeModel/closeTarget(for:from:open:)``).
    case closeOverlay
    case none

    init(_ interaction: ShapeInteraction) {
        switch (interaction.actionType, interaction.destination) {
        case let ("navigate", destination?):
            self = .navigate(to: destination, animation: interaction.animation,
                             preserveScroll: interaction.preserveScroll ?? false)
        case ("prev-screen", _):
            self = .back
        case ("open-url", _):
            self = Self.url(interaction.url).map(PrototypeAction.openURL) ?? .none
        case let ("open-overlay", destination?):
            self = .openOverlay(destination)
        case let ("toggle-overlay", destination?):
            self = .toggleOverlay(destination)
        case ("close-overlay", _):
            self = .closeOverlay
        default:
            self = .none
        }
    }

    /// Penpot opens the URL as typed (`dom/open-new-window`); a browser resolves one without
    /// a scheme against the viewer's own address, which never means anything useful, so it
    /// gets `https://`.
    static func url(_ string: String?) -> URL? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        if let url = URL(string: string), let scheme = url.scheme, !scheme.isEmpty,
           string.contains("://") || scheme == "mailto" || scheme == "tel" {
            return url
        }
        return URL(string: "https://" + string)
    }
}

/// A transition between two boards, worked out from Penpot's `animate-go-to-frame`
/// (`ui/viewer/interactions.cljs`). Distances are fractions of the stage, the moving
/// board's travel being the whole stage (Penpot moves it from just outside the wrapper).
struct PrototypeTransition: Equatable {
    enum Kind: Equatable { case none, dissolve, slideIn, slideOut, push }

    let kind: Kind
    /// Where the moving board heads: (1, 0) is right, (0, -1) up.
    let direction: CGVector
    let duration: TimeInterval
    /// CSS cubic-bezier control points of the easing.
    let controlPoints: (CGPoint, CGPoint)
    let offsetEffect: Bool

    static let instant = PrototypeTransition(kind: .none, direction: .zero, duration: 0,
                                              controlPoints: (.zero, CGPoint(x: 1, y: 1)),
                                              offsetEffect: false)

    init(kind: Kind, direction: CGVector, duration: TimeInterval,
         controlPoints: (CGPoint, CGPoint), offsetEffect: Bool) {
        self.kind = kind
        self.direction = direction
        self.duration = duration
        self.controlPoints = controlPoints
        self.offsetEffect = offsetEffect
    }

    init(_ animation: PrototypeAnimation?) {
        guard let animation, let type = animation.animationType else {
            self = .instant
            return
        }
        let kind: Kind = switch type {
        case "slide": animation.way == "out" ? .slideOut : .slideIn
        case "push": .push
        // Penpot's own types are these three; anything newer at least fades.
        default: .dissolve
        }
        self.init(kind: kind,
                  direction: Self.vector(animation.direction),
                  duration: max(0, animation.duration ?? 300) / 1000,
                  controlPoints: Self.controlPoints(animation.easing),
                  offsetEffect: animation.offsetEffect ?? false)
    }

    /// The same animation in the opposite direction (`ctsi/invert-direction`): how an
    /// overlay toggled off, or closed by a tap outside, leaves.
    var inverted: PrototypeTransition {
        PrototypeTransition(kind: kind, direction: CGVector(dx: -direction.dx, dy: -direction.dy),
                            duration: duration, controlPoints: controlPoints, offsetEffect: offsetEffect)
    }

    static func vector(_ direction: String?) -> CGVector {
        switch direction {
        case "left": CGVector(dx: -1, dy: 0)
        case "up": CGVector(dx: 0, dy: -1)
        case "down": CGVector(dx: 0, dy: 1)
        default: CGVector(dx: 1, dy: 0)
        }
    }

    /// The CSS easing keywords as cubic-bezier control points.
    static func controlPoints(_ easing: String?) -> (CGPoint, CGPoint) {
        switch easing {
        case "linear": (CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1))
        case "ease-in": (CGPoint(x: 0.42, y: 0), CGPoint(x: 1, y: 1))
        case "ease-out": (CGPoint(x: 0, y: 0), CGPoint(x: 0.58, y: 1))
        case "ease-in-out": (CGPoint(x: 0.42, y: 0), CGPoint(x: 0.58, y: 1))
        default: (CGPoint(x: 0.25, y: 0.1), CGPoint(x: 0.25, y: 1))   // CSS `ease`
        }
    }

    /// Start and end offsets (fractions of the stage) and opacities of both boards.
    struct Motion: Equatable {
        var newFrom = CGVector.zero, newTo = CGVector.zero
        var oldFrom = CGVector.zero, oldTo = CGVector.zero
        var newAlphaFrom: CGFloat = 1, oldAlphaTo: CGFloat = 1
        /// The old board stays above the new one while it moves out.
        var oldOnTop = false
    }

    var motion: Motion {
        let d = direction
        var m = Motion()
        switch kind {
        case .none:
            break
        case .dissolve:
            m.newAlphaFrom = 0
            m.oldAlphaTo = 0
        case .push:
            m.newFrom = CGVector(dx: -d.dx, dy: -d.dy)
            m.oldTo = d
        case .slideIn:
            m.newFrom = CGVector(dx: -d.dx, dy: -d.dy)
            if offsetEffect {
                m.oldTo = CGVector(dx: d.dx * 0.2, dy: d.dy * 0.2)
                m.oldAlphaTo = 0
            }
        case .slideOut:
            m.oldOnTop = true
            m.oldTo = d
            if offsetEffect {
                m.newFrom = CGVector(dx: -d.dx * 0.2, dy: -d.dy * 0.2)
                m.newAlphaFrom = 0
            }
        }
        return m
    }

    /// Where an overlay opening with this animation starts (`animate-open-overlay`): it
    /// fades in where it opens, or slides in from the edge of the screen behind its
    /// direction (way and offset effect don't apply; push counts as slide). `visible` is
    /// the screen in the board's coordinates.
    func overlayStart(_ frame: CGRect, visible: CGRect) -> (origin: CGPoint, alpha: CGFloat) {
        switch kind {
        case .none: return (frame.origin, 1)
        case .dissolve: return (frame.origin, 0)
        case .slideIn, .slideOut, .push:
            if direction.dx > 0 { return (CGPoint(x: visible.minX - frame.width, y: frame.minY), 1) }
            if direction.dx < 0 { return (CGPoint(x: visible.maxX, y: frame.minY), 1) }
            if direction.dy < 0 { return (CGPoint(x: frame.minX, y: visible.maxY), 1) }
            return (CGPoint(x: frame.minX, y: visible.minY - frame.height), 1)
        }
    }

    /// Where a closing overlay ends (`animate-close-overlay`): it fades out, or slides off
    /// the screen in its direction.
    func overlayEnd(_ frame: CGRect, visible: CGRect) -> (origin: CGPoint, alpha: CGFloat) {
        switch kind {
        case .none: return (frame.origin, 1)
        case .dissolve: return (frame.origin, 0)
        case .slideIn, .slideOut, .push:
            if direction.dx > 0 { return (CGPoint(x: visible.maxX, y: frame.minY), 1) }
            if direction.dx < 0 { return (CGPoint(x: visible.minX - frame.width, y: frame.minY), 1) }
            if direction.dy < 0 { return (CGPoint(x: frame.minX, y: visible.minY - frame.height), 1) }
            return (CGPoint(x: frame.minX, y: visible.maxY), 1)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.direction == rhs.direction && lhs.duration == rhs.duration
            && lhs.controlPoints.0 == rhs.controlPoints.0 && lhs.controlPoints.1 == rhs.controlPoints.1
            && lhs.offsetEffect == rhs.offsetEffect
    }
}

/// How a board fits the screen, as Penpot's viewer zoom menu offers it.
enum PrototypeZoom: String, Hashable, CaseIterable {
    /// The whole board on screen (`zoom-to-fit`).
    case fit
    /// The board covering the screen, scrolling where it is longer (`zoom-to-fill`).
    case fill
    /// One design pixel to one point.
    case actual

    func scale(board: CGSize, viewport: CGSize) -> CGFloat {
        guard board.width > 0, board.height > 0, viewport.width > 0, viewport.height > 0 else { return 1 }
        let w = viewport.width / board.width, h = viewport.height / board.height
        switch self {
        case .fit: return min(w, h)
        case .fill: return max(w, h)
        case .actual: return 1
        }
    }
}
