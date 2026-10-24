import XCTest
@testable import TunerCore

final class CapabilitiesTests: XCTestCase {
    let sample = "(prot(monitor)type(lcd)model(XV272K V5)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 08 10 12 14(01 05 08 0B) 16 18 1A 52 60(0F 11 12) 62 AC AE B2 B6 C6 C8 C9 D6(01 04 05) DC(00 03 05) DF)mswhql(1)asset_eep(40)mccs_ver(2.2))"

    func testParsesCodesValuesAndHeader() throws {
        let caps = try XCTUnwrap(MonitorCapabilities.parse(sample))
        XCTAssertEqual(caps.model, "XV272K V5")
        XCTAssertEqual(caps.mccsVersion, "2.2")
        XCTAssertTrue(caps.supports(0x10))
        XCTAssertTrue(caps.supports(0x12))
        XCTAssertEqual(caps.vcp[0x14] ?? [], [0x01, 0x05, 0x08, 0x0B])
        XCTAssertEqual(caps.vcp[0x60] ?? [], [0x0F, 0x11, 0x12])
        XCTAssertEqual(caps.vcp[0x10] ?? [9], [])
        XCTAssertTrue(caps.supports(VCP.colorPreset, value: ColorPreset.sRGB.rawValue))
        XCTAssertFalse(caps.supports(VCP.colorPreset, value: ColorPreset.native.rawValue))
        XCTAssertFalse(caps.supports(0x87))
    }

    func testCodesWithoutSpaces() throws {
        let caps = try XCTUnwrap(MonitorCapabilities.parse("(vcp(021012 14(0508)60(0F11))mccs_ver(2.1))"))
        XCTAssertTrue(caps.supports(0x02))
        XCTAssertTrue(caps.supports(0x10))
        XCTAssertTrue(caps.supports(0x12))
        XCTAssertEqual(caps.vcp[0x14] ?? [], [0x05, 0x08])
        XCTAssertEqual(caps.vcp[0x60] ?? [], [0x0F, 0x11])
    }

    func testVcpNameSectionIsNotMistakenForVcp() throws {
        let caps = try XCTUnwrap(MonitorCapabilities.parse("(vcpname(14(sRGB Warm))vcp(10 12))"))
        XCTAssertEqual(caps.vcp.keys.sorted(), [0x10, 0x12])
    }

    func testTruncatedStringStillParses() throws {
        let caps = try XCTUnwrap(MonitorCapabilities.parse("(prot(monitor)vcp(10 12 14(05 0B"))
        XCTAssertEqual(caps.vcp[0x14] ?? [], [0x05, 0x0B])
    }

    func testNoVcpSectionIsRejected() {
        XCTAssertNil(MonitorCapabilities.parse("(prot(monitor)type(lcd))"))
        XCTAssertNil(MonitorCapabilities.parse(""))
    }

    func testDescribedControls() throws {
        let caps = try XCTUnwrap(MonitorCapabilities.parse(sample))
        XCTAssertTrue(caps.describedControls.contains("Brightness"))
        XCTAssertTrue(caps.describedControls.contains("Colour presets (sRGB, 6500 K, 9300 K, User 1)"))
    }

    func testCapabilitiesReplyFragment() throws {
        let text = Array("vcp(10 12)".utf8)
        var reply: [UInt8] = [0x6E, 0x80 | UInt8(3 + text.count), 0xE3, 0x00, 0x20] + text
        reply.append(reply.reduce(0x50, ^))
        let data = try XCTUnwrap(DDCPacket.parseCapabilitiesReply(reply + [0, 0, 0], offset: 0x20))
        XCTAssertEqual(data, text)
        XCTAssertNil(DDCPacket.parseCapabilitiesReply(reply, offset: 0x00))
        var corrupt = reply
        corrupt[6] ^= 0x01
        XCTAssertNil(DDCPacket.parseCapabilitiesReply(corrupt, offset: 0x20))
    }

    func testEmptyFragmentEndsTheString() throws {
        var reply: [UInt8] = [0x6E, 0x83, 0xE3, 0x01, 0x00]
        reply.append(reply.reduce(0x50, ^))
        let data = try XCTUnwrap(DDCPacket.parseCapabilitiesReply(reply, offset: 0x100))
        XCTAssertTrue(data.isEmpty)
    }

    func testRequestBody() {
        XCTAssertEqual(DDCPacket.capabilitiesRequestBody(offset: 0x0120), [0x83, 0xF3, 0x01, 0x20])
    }
}

final class CapabilityEngineTests: XCTestCase {
    func acer(preset: UInt16, capabilities: String?) -> DisplayFacts {
        var acer = Fixtures.acer(ddc: .available([
            VCP.brightness: VCPValue(current: 80, max: 100),
            VCP.contrast: VCPValue(current: 50, max: 100),
            VCP.colorPreset: VCPValue(current: preset, max: 11)
        ]))
        acer.capabilities = capabilities.flatMap(MonitorCapabilities.parse)
        return acer
    }

    func change(_ id: String, in rec: Recommendation) -> PlannedChange? {
        rec.changes.first { $0.id == id }
    }

    /// Acer documents no DDC/CI colour presets and warns against adjusting
    /// undocumented controls, so no preset ever plans a 0x14 write, even
    /// when the monitor lists sRGB among its values.
    func testNoPresetEverWritesTheColourPreset() {
        for capabilities in ["(vcp(10 12 14(01 05 0B)))", nil] {
            for preset: UInt16 in [0x01, 0x05] {
                let display = acer(preset: preset, capabilities: capabilities)
                for useCase in UseCase.allCases {
                    let rec = RecommendationEngine.recommend(useCase, for: display, context: EngineContext(lighting: .normal, allDisplays: [display]))
                    XCTAssertFalse(rec.changes.contains {
                        if case .ddc(let target) = $0.change { return target.vcp == VCP.colorPreset }
                        return false
                    }, "\(useCase) planned a colour-preset write")
                }
            }
        }
    }
}

final class AppRulesTests: XCTestCase {
    func testEditorsByBundleID() {
        XCTAssertEqual(AppRules.useCase(bundleID: "com.adobe.LightroomClassicCC7", category: nil, path: nil, gamePreset: .competitiveGaming), .photoEditing)
        XCTAssertEqual(AppRules.useCase(bundleID: "com.adobe.Photoshop", category: nil, path: nil, gamePreset: .competitiveGaming), .photoEditing)
        XCTAssertEqual(AppRules.useCase(bundleID: "com.captureone.captureone16", category: nil, path: nil, gamePreset: .competitiveGaming), .photoEditing)
        XCTAssertEqual(AppRules.useCase(bundleID: "com.apple.FinalCut", category: nil, path: nil, gamePreset: .competitiveGaming), .videoEditing)
        XCTAssertEqual(AppRules.useCase(bundleID: "com.blackmagic-design.DaVinciResolveLite", category: nil, path: nil, gamePreset: .competitiveGaming), .videoEditing)
    }

    func testGamesByCategoryOrSteamFolder() {
        XCTAssertEqual(AppRules.useCase(bundleID: "com.example.shooter", category: "public.app-category.action-games", path: nil, gamePreset: .competitiveGaming), .competitiveGaming)
        XCTAssertEqual(AppRules.useCase(bundleID: "com.example.rpg", category: "public.app-category.games", path: nil, gamePreset: .immersiveGaming), .immersiveGaming)
        XCTAssertEqual(AppRules.useCase(bundleID: nil, category: nil, path: "/Users/me/Library/Application Support/Steam/steamapps/common/Game/Game.app", gamePreset: .immersiveGaming), .immersiveGaming)
    }

    func testOtherAppsHaveNoPreset() {
        XCTAssertNil(AppRules.useCase(bundleID: "com.apple.Safari", category: "public.app-category.productivity", path: "/Applications/Safari.app", gamePreset: .competitiveGaming))
        XCTAssertNil(AppRules.useCase(bundleID: "com.valvesoftware.steam", category: nil, path: "/Applications/Steam.app", gamePreset: .competitiveGaming))
        XCTAssertNil(AppRules.useCase(bundleID: nil, category: "public.app-category.games-news", path: nil, gamePreset: .competitiveGaming))
    }
}
