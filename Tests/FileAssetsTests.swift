import XCTest
@testable import PenpotiOS

/// A file's library as `get-file` sends it (the Assets view), its design tokens in
/// Penpot's DTCG format with references and formulas resolved, and the accounts' small
/// pieces of logic.
final class FileAssetsTests: XCTestCase {

    // MARK: Assets from get-file

    private let fileJSON = """
        {"id":"f1","name":"Lib","revn":3,"data":{
          "pages":["p1"],
          "pagesIndex":{"p1":{"id":"p1","name":"Main","objects":{
            "00000000-0000-0000-0000-000000000000":{"id":"00000000-0000-0000-0000-000000000000","type":"frame","shapes":["b1"]},
            "b1":{"id":"b1","type":"frame","parentId":"00000000-0000-0000-0000-000000000000","selrect":{"x":0,"y":0,"width":400,"height":300},"shapes":["c1"]},
            "c1":{"id":"c1","type":"frame","parentId":"b1","selrect":{"x":10,"y":20,"width":120,"height":40},"mainInstance":true,"componentId":"k1"}}}},
          "components":{
            "k1":{"id":"k1","name":"Button","path":"Buttons / Primary","mainInstanceId":"c1","mainInstancePage":"p1",
                  "variantProperties":[{"name":"Size","value":"Large"}]},
            "k2":{"id":"k2","name":"Gone","path":"","mainInstanceId":"x","mainInstancePage":"p1","deleted":true},
            "k3":{"id":"k3","name":"Legacy","path":"Old"}},
          "colors":{
            "c2":{"id":"c2","name":"Primary","path":"Brand","color":"#00c38b","opacity":0.5},
            "c3":{"id":"c3","name":"Fade","gradient":{"type":"linear","startX":0,"startY":0,"endX":1,"endY":1,
                  "stops":[{"color":"#000000","opacity":1,"offset":0},{"color":"#ffffff","opacity":1,"offset":1}]}},
            "bad":{"id":"bad"}},
          "typographies":{
            "t1":{"id":"t1","name":"Body","path":"","fontId":"gfont-work-sans","fontFamily":"Work Sans","fontVariantId":"regular",
                  "fontSize":"16","fontWeight":"400","fontStyle":"normal","lineHeight":"1.5","letterSpacing":"0","textTransform":"none"},
            "t2":{"id":"t2","name":"Old","fontId":"sourcesanspro","fontFamily":"sourcesanspro","fontVariantId":"bold",
                  "fontSize":24,"fontWeight":700,"fontStyle":"italic","lineHeight":1.2,"letterSpacing":0.5}},
          "media":{"m1":{"id":"m1","name":"logo.svg","path":"icons","width":40,"height":40,"mtype":"image/svg+xml"}}
        }}
        """

    func testAssetsComeWithTheOutline() throws {
        let file = try JSONDecoder.penpot.decode(PenpotFile.self, from: Data(fileJSON.utf8))
        let assets = try XCTUnwrap(file.outline.assets)
        XCTAssertEqual(assets.components.map(\.name), ["Button", "Legacy"], "By group, then name.")
        XCTAssertEqual(Set(assets.components.map(\.id)), ["k1", "k3"], "A deleted component isn't listed.")
        let button = try XCTUnwrap(assets.components.first { $0.id == "k1" })
        XCTAssertEqual(button.groupPath, "Buttons / Primary")
        XCTAssertEqual(button.variantSummary, "Size: Large")
        let board = try XCTUnwrap(button.mainInstance, "The main copy is drawn from its page.")
        XCTAssertEqual(board.id, "c1")
        XCTAssertEqual(board.pageID, "p1")
        XCTAssertEqual(board.selrect, Selrect(x: 10, y: 20, width: 120, height: 40))
        XCTAssertNil(assets.components.first { $0.id == "k3" }?.mainInstance, "A v1 component has no main copy.")

        XCTAssertEqual(assets.colors.count, 2, "A color that doesn't decode is left out, not the others.")
        XCTAssertEqual(assets.colors.first { $0.id == "c2" }?.valueText, "#00C38B 50 %")
        XCTAssertEqual(assets.colors.first { $0.id == "c3" }?.gradient?.stops.count, 2)

        let old = try XCTUnwrap(assets.typographies.first { $0.id == "t2" })
        XCTAssertEqual(old.fontSize, "24", "Numbers read as Penpot's strings.")
        XCTAssertEqual(old.letterSpacing, "0.5")
        XCTAssertTrue(old.css.contains("font-style: italic;"))
        let body = try XCTUnwrap(assets.typographies.first { $0.id == "t1" })
        XCTAssertEqual(body.css, """
            font-family: "Work Sans";
            font-size: 16px;
            font-weight: 400;
            line-height: 1.5;
            letter-spacing: 0px;
            """)

        XCTAssertEqual(assets.media.first?.isSVG, true)
        XCTAssertEqual(assets.media.first?.url(server: URL(string: "https://penpot.test")!).absoluteString,
                       "https://penpot.test/assets/by-file-media-id/m1")
        XCTAssertFalse(assets.isEmpty)
    }

    func testGroupsKeepTheirOrder() throws {
        let file = try JSONDecoder.penpot.decode(PenpotFile.self, from: Data(fileJSON.utf8))
        let groups = try XCTUnwrap(file.outline.assets).components.grouped
        XCTAssertEqual(groups.map(\.path), ["Buttons / Primary", "Old"])
        XCTAssertEqual(try XCTUnwrap(file.outline.assets).components.matching("butt").map(\.id), ["k1"])
    }

    /// An outline cached before the library was kept still decodes, without one.
    func testOldCachedOutlineDecodes() throws {
        let json = #"{"revision":2,"pages":[]}"#
        let outline = try JSONDecoder().decode(FileOutline.self, from: Data(json.utf8))
        XCTAssertNil(outline.assets)
    }

    // MARK: Tokens

    private let tokensJSON = """
        {
          "Core": {
            "base": {"$value": "4", "$type": "dimension"},
            "space": {"$type": "spacing", "sm": {"$value": "{base} * 2"}, "md": {"$value": "{base}*3px"}},
            "blue": {"500": {"$value": "#0055ff", "$type": "color"}}
          },
          "Light": {"accent": {"$value": "{blue.500}", "$type": "color", "$description": "Main"}},
          "Dark": {"accent": {"$value": "#112233", "$type": "color"}},
          "Broken": {"loop": {"$value": "{loop}", "$type": "number"}},
          "$themes": [
            {"name": "Light", "group": "Mode", "selectedTokenSets": {"Core": "enabled", "Light": "enabled"}},
            {"name": "Dark", "group": "Mode", "selectedTokenSets": {"Core": "enabled", "Dark": "enabled"}}
          ],
          "$metadata": {"tokenSetOrder": ["Core", "Light", "Dark", "Broken"], "activeThemes": ["Mode/Light"]}
        }
        """

    private func library() throws -> TokenLibrary {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(tokensJSON.utf8))
        return try XCTUnwrap(TokenLibrary(dtcg: value))
    }

    func testSetsThemesAndActiveSets() throws {
        let tokens = try library()
        XCTAssertEqual(tokens.sets.map(\.name), ["Core", "Light", "Dark", "Broken"])
        XCTAssertEqual(Set(tokens.activeSets), ["Core", "Light"], "Without activeSets, the active themes' sets.")
        XCTAssertEqual(tokens.themes.first?.id, "Mode/Light")
        let core = tokens.sets[0]
        XCTAssertEqual(core.tokens.map(\.name), ["base", "blue.500", "space.md", "space.sm"])
        XCTAssertEqual(core.tokens.first { $0.name == "space.sm" }?.type, "spacing", "A group's $type is inherited.")
    }

    func testReferencesAndFormulasResolve() throws {
        let tokens = try library()
        let light = tokens.sets[1]
        let resolver = tokens.resolver(selecting: light)
        let core = tokens.sets[0].tokens
        XCTAssertEqual(resolver.resolve(core.first { $0.name == "space.sm" }!), "8")
        XCTAssertEqual(resolver.resolve(core.first { $0.name == "space.md" }!), "12px")
        XCTAssertEqual(resolver.resolve(light.tokens[0]), "#0055ff")
        XCTAssertEqual(light.tokens[0].description, "Main")

        // The selected set wins over the active ones, as in Penpot's panel.
        let dark = tokens.sets[2]
        XCTAssertEqual(tokens.resolver(selecting: dark).resolve(dark.tokens[0]), "#112233")
        XCTAssertFalse(tokens.isActive(dark))

        let broken = tokens.sets[3]
        XCTAssertNil(tokens.resolver(selecting: broken).resolve(broken.tokens[0]), "A circular reference doesn't resolve.")
    }

    func testArithmetic() {
        XCTAssertEqual(TokenResolver.evaluate("4 * 3"), "12")
        XCTAssertEqual(TokenResolver.evaluate("(2 + 2) * 1.5"), "6")
        XCTAssertEqual(TokenResolver.evaluate("16px / 3"), "5.333px")
        XCTAssertNil(TokenResolver.evaluate("4px * 2rem"), "Two units don't mix.")
        XCTAssertNil(TokenResolver.evaluate("#ff0000"))
        XCTAssertNil(TokenResolver.evaluate("rgba(0, 0, 0, 0.5)"))
        XCTAssertNil(TokenResolver.evaluate("Work Sans"))
    }

    func testTypeGroupsFollowPenpotsOrder() throws {
        let tokens = try library()
        let groups = TokenLibrary.groups(tokens.sets[0].tokens)
        XCTAssertEqual(groups.map(\.type.title), ["Color", "Dimensions", "Spacing"])
    }

    func testCompositeValuesListTheirParts() throws {
        let json = #"{"S":{"h1":{"$type":"typography","$value":{"fontSize":"32","fontWeight":"700"}}}}"#
        let tokens = try XCTUnwrap(TokenLibrary(dtcg: JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))))
        XCTAssertEqual(tokens.sets[0].tokens[0].value, "Font Size: 32\nFont Weight: 700")
    }

    func testColors() {
        XCTAssertEqual(ParsedColor("#fff"), ParsedColor(red: 1, green: 1, blue: 1, alpha: 1))
        XCTAssertEqual(ParsedColor("#00000080")?.alpha ?? 0, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(ParsedColor("rgba(255, 0, 0, 0.5)"), ParsedColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        XCTAssertEqual(ParsedColor("transparent")?.alpha, 0)
        XCTAssertNil(ParsedColor("{accent}"))
    }

    // MARK: Accounts

    func testSameLogin() {
        let account = StoredAccount(id: "a", server: URL(string: "https://design.penpot.app")!,
                                    email: "Me@Example.com", profileID: nil)
        XCTAssertTrue(account.isSameLogin(server: URL(string: "https://design.penpot.app")!,
                                          email: "me@example.com", profileID: nil))
        XCTAssertFalse(account.isSameLogin(server: URL(string: "http://localhost:3450")!,
                                           email: "me@example.com", profileID: nil))
        var withProfile = account
        withProfile.profileID = "p1"
        XCTAssertFalse(withProfile.isSameLogin(server: account.server, email: "me@example.com", profileID: "p2"),
                       "The profile decides where both have one.")
        XCTAssertEqual(StoredAccount(id: "b", server: URL(string: "http://localhost:3450")!).serverLabel, "localhost:3450")
        XCTAssertEqual(account.serverLabel, "design.penpot.app")
    }
}
