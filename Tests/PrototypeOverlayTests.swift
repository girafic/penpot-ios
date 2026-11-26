import XCTest
@testable import PenpotiOS

/// The native player's overlays and shapes fixed when scrolling, after Penpot's
/// `calc-overlay-position`, `animate-open-overlay`/`-close-overlay` and `fixed-scroll?`.
final class PrototypeOverlayTests: XCTestCase {
    private let root = Board.rootFrameID

    /// "Screen" (0,0, 400×2000) scrolls. Its menu button opens "Menu" at a manual position
    /// with a dimmed background; its info rect toggles "Tip" at the bottom centre of
    /// itself; its tab bar is fixed when scrolling; a rect marked fixed inside a group
    /// doesn't count (Penpot only fixes a frame's direct children). "Menu" has a close
    /// button without a destination.
    private func model() throws -> PrototypeModel {
        let json = """
        {
          "id": "p", "name": "Page",
          "objects": {
            "\(root)": {"id": "\(root)", "type": "frame", "shapes": ["screen", "menu", "tip"],
                        "selrect": {"x": 0, "y": 0, "width": 0.01, "height": 0.01}},
            "screen": {"id": "screen", "type": "frame", "parentId": "\(root)", "frameId": "\(root)",
                       "fills": [{}], "shapes": ["menu-button", "info", "group", "nav"],
                       "selrect": {"x": 0, "y": 0, "width": 400, "height": 2000}},
            "menu-button": {"id": "menu-button", "type": "rect", "parentId": "screen", "frameId": "screen",
                            "selrect": {"x": 20, "y": 40, "width": 40, "height": 40},
                            "interactions": [{"eventType": "click", "actionType": "open-overlay", "destination": "menu",
                                              "overlayPosType": "manual", "overlayPosition": {"x": 10, "y": 90},
                                              "closeClickOutside": true, "backgroundOverlay": true,
                                              "animation": {"animationType": "slide", "direction": "left",
                                                            "duration": 300, "easing": "ease-out"}}]},
            "info": {"id": "info", "type": "rect", "parentId": "screen", "frameId": "screen",
                     "selrect": {"x": 300, "y": 700, "width": 80, "height": 40},
                     "interactions": [{"eventType": "click", "actionType": "toggle-overlay", "destination": "tip",
                                       "overlayPosType": "bottom-center", "positionRelativeTo": "info"}]},
            "group": {"id": "group", "type": "group", "parentId": "screen", "frameId": "screen",
                      "shapes": ["grouped"], "selrect": {"x": 0, "y": 300, "width": 50, "height": 50}},
            "grouped": {"id": "grouped", "type": "rect", "parentId": "group", "frameId": "screen", "fixedScroll": true,
                        "selrect": {"x": 0, "y": 300, "width": 50, "height": 50}},
            "nav": {"id": "nav", "type": "rect", "parentId": "screen", "frameId": "screen", "fixedScroll": true,
                    "selrect": {"x": 0, "y": 740, "width": 400, "height": 60},
                    "interactions": [{"eventType": "click", "actionType": "navigate", "destination": "menu"}]},
            "menu": {"id": "menu", "type": "frame", "parentId": "\(root)", "frameId": "\(root)", "fills": [{}],
                     "shapes": ["close"], "selrect": {"x": 500, "y": 0, "width": 300, "height": 400}},
            "close": {"id": "close", "type": "rect", "parentId": "menu", "frameId": "menu",
                      "selrect": {"x": 510, "y": 10, "width": 30, "height": 30},
                      "interactions": [{"eventType": "click", "actionType": "close-overlay"}]},
            "tip": {"id": "tip", "type": "frame", "parentId": "\(root)", "frameId": "\(root)", "fills": [{}],
                    "selrect": {"x": 900, "y": 0, "width": 120, "height": 60}}
          }
        }
        """
        return PrototypeModel(pageID: "p", page: try JSONDecoder().decode(PenpotPage.self, from: Data(json.utf8)))
    }

    private func interaction(_ model: PrototypeModel, _ shape: String) -> ShapeInteraction {
        model.page.objects[shape]!.interactions!.first!
    }

    // MARK: Positions

    /// A manual position counts from the board the overlay opens on: the source's own
    /// offset cancels out.
    func testManualOverlayOpensAtItsPosition() throws {
        let model = try model()
        let frame = model.overlayFrame(for: interaction(model, "menu-button"), from: "menu-button", baseBoard: "screen")
        XCTAssertEqual(frame, CGRect(x: 10, y: 90, width: 300, height: 400))
    }

    func testOverlayPlacedAgainstAShape() throws {
        let model = try model()
        let frame = model.overlayFrame(for: interaction(model, "info"), from: "info", baseBoard: "screen")
        // Bottom centre of the info rect (300,700, 80×40) for a 120×60 overlay.
        XCTAssertEqual(frame, CGRect(x: 280, y: 680, width: 120, height: 60))
    }

    /// No position and nothing to place against: centred on the board.
    func testDefaultOverlayIsCentredOnTheBoard() throws {
        let model = try model()
        let frame = model.overlayFrame(for: ShapeInteraction(actionType: "open-overlay", destination: "menu"),
                                       from: "info", baseBoard: "screen")
        XCTAssertEqual(frame, CGRect(x: 50, y: 800, width: 300, height: 400))
    }

    /// An overlay opened from inside another counts from that one's position.
    func testOverlayFromAnOverlayCountsFromIt() throws {
        let model = try model()
        let frame = model.overlayFrame(for: interaction(model, "info"), from: "info", baseBoard: "screen",
                                       frameOffset: CGPoint(x: 5, y: 7), overlaysOpen: true)
        XCTAssertEqual(frame?.origin, CGPoint(x: 285, y: 687))
    }

    func testCloseWithoutDestinationClosesTheOverlayItIsIn() throws {
        let model = try model()
        XCTAssertEqual(model.closeTarget(for: interaction(model, "close"), from: "close", open: ["tip", "menu"]), "menu")
        XCTAssertEqual(model.closeTarget(for: ShapeInteraction(actionType: "close-overlay", destination: "tip"),
                                         from: "close", open: ["menu"]), "tip")
    }

    func testOverlayDestinationsRenderAhead() throws {
        XCTAssertEqual(Set(try model().destinations(fromBoard: "screen")), ["menu", "tip"])
    }

    // MARK: Animations

    /// Slide left: the overlay comes in from the right edge of the screen; toggled off or
    /// closed by a tap outside it goes back the way it came.
    func testOverlaySlidesFromTheScreenEdge() {
        let open = PrototypeTransition(PrototypeAnimation(animationType: "slide", duration: 300, easing: "ease-out",
                                                          direction: "left", way: nil, offsetEffect: nil))
        let frame = CGRect(x: 10, y: 90, width: 300, height: 400)
        let screen = CGRect(x: 0, y: 100, width: 400, height: 800)
        XCTAssertEqual(open.overlayStart(frame, visible: screen).origin, CGPoint(x: 400, y: 90))
        XCTAssertEqual(open.inverted.overlayEnd(frame, visible: screen).origin, CGPoint(x: 400, y: 90))
        let up = PrototypeTransition(PrototypeAnimation(animationType: "slide", duration: 300, easing: nil,
                                                        direction: "up", way: nil, offsetEffect: nil))
        XCTAssertEqual(up.overlayStart(frame, visible: screen).origin, CGPoint(x: 10, y: 900))
        XCTAssertEqual(up.overlayEnd(frame, visible: screen).origin, CGPoint(x: 10, y: -300))
        let fade = PrototypeTransition(PrototypeAnimation(animationType: "dissolve", duration: 200, easing: nil,
                                                          direction: nil, way: nil, offsetEffect: nil))
        XCTAssertEqual(fade.overlayStart(frame, visible: screen).alpha, 0)
        XCTAssertEqual(fade.overlayEnd(frame, visible: screen).origin, frame.origin)
    }

    // MARK: Fixed when scrolling

    func testOnlyAFramesDirectChildrenAreFixed() throws {
        XCTAssertEqual(try model().fixedShapes(onBoard: "screen"), ["nav"])
    }

    /// Scrolled 500 down, the tab bar shows 500 further down the board, and takes the tap
    /// there; where it was drawn, the board is.
    func testFixedShapesTakeTapsWhereTheyShow() throws {
        let model = try model()
        let scroll = CGPoint(x: 0, y: 500)
        XCTAssertEqual(model.tap(at: CGPoint(x: 200, y: 1270), onBoard: "screen", scroll: scroll)?.shapeID, "nav")
        XCTAssertNil(model.tap(at: CGPoint(x: 200, y: 770), onBoard: "screen", scroll: scroll))
        XCTAssertEqual(model.tap(at: CGPoint(x: 200, y: 770), onBoard: "screen")?.shapeID, "nav")
        XCTAssertTrue(model.hotspots(onBoard: "screen", scroll: scroll).contains(CGRect(x: 0, y: 1240, width: 400, height: 60)))
    }

    func testAnOverlayPlacedAgainstAFixedShapeIsFixed() throws {
        let model = try model()
        let manual = ShapeInteraction(actionType: "open-overlay", destination: "tip", overlayPosType: "manual")
        XCTAssertTrue(model.isFixedSource(manual, from: "nav"))
        XCTAssertFalse(model.isFixedSource(interaction(model, "info"), from: "info"))
    }
}
