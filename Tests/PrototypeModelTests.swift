import XCTest
@testable import PenpotiOS

/// The native prototype player's rules (``PrototypeModel``), from Penpot's viewer
/// (`ui/viewer/shapes.cljs`, `ui/viewer/interactions.cljs`).
final class PrototypeModelTests: XCTestCase {
    private let root = Board.rootFrameID

    /// Two boards side by side. "Home" (100,100, 400×800) holds a button group with an
    /// interaction (its rect and label have none), a rect with its own interaction that a
    /// later sibling text covers, a fill-less nested board with a hotspot in it, a hidden
    /// rect with an interaction, and a link. "Home" goes to "Next" after a delay.
    private func page() throws -> PenpotPage {
        let json = """
        {
          "id": "page-1", "name": "Flows",
          "flows": {"f1": {"id": "f1", "name": "Onboarding", "startingFrame": "next"},
                    "f0": {"id": "f0", "name": "Checkout", "startingFrame": "home"}},
          "objects": {
            "\(root)": {"id": "\(root)", "type": "frame", "shapes": ["home", "next"],
                        "selrect": {"x": 0, "y": 0, "width": 0.01, "height": 0.01}},
            "home": {"id": "home", "name": "Home", "type": "frame", "parentId": "\(root)",
                     "frameId": "\(root)", "fills": [{"fillColor": "#ffffff"}],
                     "shapes": ["button", "covered", "cover", "inner", "ghost", "link"],
                     "selrect": {"x": 100, "y": 100, "width": 400, "height": 800},
                     "interactions": [{"eventType": "after-delay", "actionType": "navigate",
                                       "destination": "next", "delay": 2000}]},
            "button": {"id": "button", "type": "group", "parentId": "home", "frameId": "home",
                       "shapes": ["button-bg", "button-label"],
                       "selrect": {"x": 120, "y": 700, "width": 360, "height": 60},
                       "interactions": [{"eventType": "click", "actionType": "navigate",
                                         "destination": "next", "preserveScroll": true,
                                         "animation": {"animationType": "push", "direction": "left",
                                                       "duration": 450, "easing": "ease-in-out"}}]},
            "button-bg": {"id": "button-bg", "type": "rect", "parentId": "button", "frameId": "home",
                          "selrect": {"x": 120, "y": 700, "width": 360, "height": 60}},
            "button-label": {"id": "button-label", "type": "text", "parentId": "button", "frameId": "home",
                             "selrect": {"x": 200, "y": 715, "width": 200, "height": 30}},
            "covered": {"id": "covered", "type": "rect", "parentId": "home", "frameId": "home",
                        "selrect": {"x": 120, "y": 200, "width": 200, "height": 100},
                        "interactions": [{"actionType": "prev-screen"}]},
            "cover": {"id": "cover", "type": "text", "parentId": "home", "frameId": "home",
                      "selrect": {"x": 120, "y": 200, "width": 100, "height": 100}},
            "inner": {"id": "inner", "type": "frame", "parentId": "home", "frameId": "home",
                      "shapes": ["chip"],
                      "selrect": {"x": 120, "y": 400, "width": 360, "height": 200}},
            "chip": {"id": "chip", "type": "rect", "parentId": "inner", "frameId": "inner",
                     "selrect": {"x": 140, "y": 420, "width": 80, "height": 40},
                     "interactions": [{"eventType": "mouse-press", "actionType": "open-overlay",
                                       "destination": "next"}]},
            "ghost": {"id": "ghost", "type": "rect", "parentId": "home", "frameId": "home", "hidden": true,
                      "selrect": {"x": 300, "y": 120, "width": 100, "height": 50},
                      "interactions": [{"eventType": "click", "actionType": "prev-screen"}]},
            "link": {"id": "link", "type": "text", "parentId": "home", "frameId": "home",
                     "selrect": {"x": 400, "y": 850, "width": 80, "height": 30},
                     "interactions": [{"eventType": "mouse-enter", "actionType": "navigate", "destination": "next"},
                                      {"eventType": "click", "actionType": "open-url", "url": "penpot.app"}]},
            "next": {"id": "next", "name": "Next", "type": "frame", "parentId": "\(root)",
                     "frameId": "\(root)", "fills": [],
                     "selrect": {"x": 600, "y": 100, "width": 400, "height": 800}}
          }
        }
        """
        return try JSONDecoder().decode(PenpotPage.self, from: Data(json.utf8))
    }

    private func model() throws -> PrototypeModel {
        PrototypeModel(pageID: "page-1", page: try page())
    }

    // MARK: Decoding

    func testDecodesInteractionsAsPenpotExportsThem() throws {
        let page = try page()
        let button = try XCTUnwrap(page.objects["button"]?.interactions?.first)
        XCTAssertEqual(button.eventType, "click")
        XCTAssertEqual(button.destination, "next")
        XCTAssertEqual(button.preserveScroll, true)
        XCTAssertEqual(button.animation?.animationType, "push")
        XCTAssertEqual(button.animation?.duration, 450)
        XCTAssertEqual(page.objects["home"]?.interactions?.first?.delay, 2000)
        XCTAssertEqual(page.objects["home"]?.hasFills, true)
        XCTAssertEqual(page.objects["next"]?.hasFills, false)
        XCTAssertEqual(page.objects["ghost"]?.hidden, true)
    }

    // MARK: Taps

    /// The label is on top, but it and its rect have no interaction: the event goes up
    /// to the group, as Penpot's DOM event bubbles.
    func testTapOnAButtonsLabelRunsTheGroupsInteraction() throws {
        let interactions = try model().tap(at: CGPoint(x: 150, y: 630), onBoard: "home")
        XCTAssertEqual(interactions?.shapeID, "button")
        XCTAssertEqual(interactions?.interactions.first?.destination, "next")
    }

    /// A sibling painted over a shape takes the tap, so the shape under it doesn't run:
    /// only the uncovered part of the rect does.
    func testACoveringSiblingSwallowsTheTap() throws {
        let model = try model()
        XCTAssertNil(model.tap(at: CGPoint(x: 50, y: 150), onBoard: "home"))
        XCTAssertEqual(model.tap(at: CGPoint(x: 170, y: 150), onBoard: "home")?.interactions.first?.actionType, "prev-screen")
    }

    /// A board without a fill paints nothing a tap lands on, but its children do; a
    /// mouse-press counts as a tap.
    func testShapesInAFillLessNestedBoardTakeTaps() throws {
        let model = try model()
        XCTAssertEqual(model.tap(at: CGPoint(x: 60, y: 340), onBoard: "home")?.interactions.first?.actionType, "open-overlay")
        XCTAssertNil(model.tap(at: CGPoint(x: 300, y: 450), onBoard: "home"))
    }

    func testHiddenShapesAndHoverEventsDontRun() throws {
        let model = try model()
        XCTAssertNil(model.tap(at: CGPoint(x: 250, y: 40), onBoard: "home"))
        let link = try XCTUnwrap(model.tap(at: CGPoint(x: 320, y: 760), onBoard: "home"))
        XCTAssertEqual(link.interactions.map(\.actionType), ["open-url"])
    }

    func testTapsOutsideTheBoardRunNothing() throws {
        XCTAssertNil(try model().tap(at: CGPoint(x: 450, y: 10), onBoard: "home"))
    }

    func testHotspotsAreInTheBoardsCoordinates() throws {
        let hotspots = Set(try model().hotspots(onBoard: "home").map { "\($0)" })
        XCTAssertTrue(hotspots.contains("\(CGRect(x: 20, y: 600, width: 360, height: 60))"))
        XCTAssertTrue(hotspots.contains("\(CGRect(x: 20, y: 100, width: 200, height: 100))"))
        XCTAssertFalse(hotspots.contains("\(CGRect(x: 200, y: 20, width: 100, height: 50))"), "hidden")
    }

    // MARK: Boards, delays, flows

    func testDelaysDestinationsAndStart() throws {
        let model = try model()
        XCTAssertEqual(model.delayedInteractions(onBoard: "home").map(\.interaction.delay), [2000])
        XCTAssertEqual(model.delayedInteractions(onBoard: "home").map(\.shapeID), ["home"])
        XCTAssertEqual(model.destinations(fromBoard: "home"), ["next"])
        XCTAssertEqual(model.flows.map(\.name), ["Checkout", "Onboarding"])
        XCTAssertEqual(model.startBoard(preferred: "next"), "next")
        XCTAssertEqual(model.startBoard(preferred: nil), "home", "the first flow by name")
        XCTAssertEqual(model.startBoard(preferred: "button"), "home", "not a board")
        XCTAssertEqual(model.board("next")?.selrect.width, 400)
        XCTAssertNil(model.board("button"))
    }

    // MARK: Actions

    func testActions() {
        XCTAssertEqual(PrototypeAction(ShapeInteraction(actionType: "prev-screen")), .back)
        XCTAssertEqual(PrototypeAction(ShapeInteraction(actionType: "toggle-overlay", destination: "x")), .toggleOverlay("x"))
        XCTAssertEqual(PrototypeAction(ShapeInteraction(actionType: "open-overlay", destination: "x")), .openOverlay("x"))
        XCTAssertEqual(PrototypeAction(ShapeInteraction(actionType: "open-overlay")), .none)
        XCTAssertEqual(PrototypeAction(ShapeInteraction(actionType: "close-overlay")), .closeOverlay)
        XCTAssertEqual(PrototypeAction(ShapeInteraction(actionType: "navigate")), .none)
        XCTAssertEqual(PrototypeAction(ShapeInteraction(actionType: "open-url", url: "penpot.app")),
                       .openURL(URL(string: "https://penpot.app")!))
        XCTAssertEqual(PrototypeAction(ShapeInteraction(actionType: "open-url", url: "http://x.test/a")),
                       .openURL(URL(string: "http://x.test/a")!))
        XCTAssertEqual(PrototypeAction(ShapeInteraction(actionType: "open-url", url: "mailto:hi@x.test")),
                       .openURL(URL(string: "mailto:hi@x.test")!))
        XCTAssertEqual(PrototypeAction(ShapeInteraction(actionType: "open-url", url: " ")), .none)
    }

    // MARK: Transitions

    private func transition(_ type: String, direction: String? = nil, way: String? = nil,
                            offset: Bool? = nil) -> PrototypeTransition {
        PrototypeTransition(PrototypeAnimation(animationType: type, duration: 400, easing: "ease-out",
                                               direction: direction, way: way, offsetEffect: offset))
    }

    /// Push left: the new board comes in from the right, the old one leaves to the left.
    func testPushMovesBothBoards() {
        let m = transition("push", direction: "left").motion
        XCTAssertEqual(m.newFrom, CGVector(dx: 1, dy: 0))
        XCTAssertEqual(m.oldTo, CGVector(dx: -1, dy: 0))
        XCTAssertEqual(transition("push").duration, 0.4)
    }

    /// Slide in up: the new board rises from below over the old one, which with the
    /// offset effect drifts a fifth up and fades.
    func testSlideInWithOffsetEffect() {
        let m = transition("slide", direction: "up", way: "in", offset: true).motion
        XCTAssertEqual(m.newFrom, CGVector(dx: 0, dy: 1))
        XCTAssertEqual(m.oldTo.dy, -0.2, accuracy: 0.0001)
        XCTAssertEqual(m.oldAlphaTo, 0)
        XCTAssertFalse(m.oldOnTop)
    }

    /// Slide out right: the old board, on top, leaves to the right over the new one.
    func testSlideOutKeepsTheOldBoardOnTop() {
        let m = transition("slide", direction: "right", way: "out").motion
        XCTAssertTrue(m.oldOnTop)
        XCTAssertEqual(m.oldTo, CGVector(dx: 1, dy: 0))
        XCTAssertEqual(m.newFrom, .zero)
    }

    func testDissolveAndUnknownTypesFade() {
        XCTAssertEqual(transition("dissolve").kind, .dissolve)
        XCTAssertEqual(transition("dissolve").motion.newAlphaFrom, 0)
        XCTAssertEqual(transition("cube").kind, .dissolve)
        XCTAssertEqual(PrototypeTransition(nil), .instant)
    }

    func testEasingsAreCSSCurves() {
        XCTAssertEqual(PrototypeTransition.controlPoints("ease-in-out").0, CGPoint(x: 0.42, y: 0))
        XCTAssertEqual(PrototypeTransition.controlPoints("ease").0, CGPoint(x: 0.25, y: 0.1))
        XCTAssertEqual(PrototypeTransition.controlPoints(nil).1, CGPoint(x: 0.25, y: 1))
    }

    // MARK: Zoom

    /// Penpot's fit is the smaller ratio, its fill the larger one.
    func testZoomStyles() {
        let board = CGSize(width: 400, height: 1600), screen = CGSize(width: 400, height: 800)
        XCTAssertEqual(PrototypeZoom.fit.scale(board: board, viewport: screen), 0.5)
        XCTAssertEqual(PrototypeZoom.fill.scale(board: board, viewport: screen), 1)
        XCTAssertEqual(PrototypeZoom.actual.scale(board: board, viewport: screen), 1)
    }
}
