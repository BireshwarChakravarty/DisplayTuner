import XCTest
@testable import TunerCore

/// Modes shaped like what macOS reports for a 27-inch 4K 160 Hz monitor.
enum Fixtures {
    static func acerModes() -> [DisplayMode] {
        var modes: [DisplayMode] = []
        var id: Int32 = 1
        func add(_ w: Int, _ h: Int, _ pw: Int, _ ph: Int, _ rates: [Double]) {
            for hz in rates {
                modes.append(DisplayMode(modeID: id, width: w, height: h, pixelWidth: pw, pixelHeight: ph, refreshRate: hz))
                id += 1
            }
        }
        add(3840, 2160, 3840, 2160, [60, 120, 144, 160])  // native
        add(1920, 1080, 3840, 2160, [60, 120, 144, 160])  // HiDPI 2×
        add(2560, 1440, 5120, 2880, [60, 120, 144, 160])  // HiDPI scaled
        add(3008, 1692, 6016, 3384, [60, 120, 144, 160])  // HiDPI scaled
        add(2560, 1440, 2560, 1440, [60, 120, 144])       // blurry, upscaled by the monitor
        add(1920, 1080, 1920, 1080, [60, 120, 144, 320])  // DFR fast mode
        return modes
    }

    static func acer(current: DisplayMode? = nil, ddc: DDCStatus = .available([
        VCP.brightness: VCPValue(current: 80, max: 100),
        VCP.contrast: VCPValue(current: 60, max: 100)
    ]), customProfile: String? = nil) -> DisplayFacts {
        let modes = acerModes()
        return DisplayFacts(
            id: 2, name: "XV272K V5", vendorID: 0x0472, productID: 0x1234, serial: 1,
            modes: modes,
            currentMode: current ?? modes.first { $0.width == 2560 && $0.pixelWidth == 5120 && $0.refreshRate == 60 },
            widthMM: 597,
            primaries: Primaries(red: XY(0.68, 0.31), green: XY(0.27, 0.66), blue: XY(0.15, 0.06)),
            customProfilePath: customProfile,
            edrHeadroom: 1,
            ddc: ddc)
    }

    static func arzopa(mirroring master: UInt32 = 2) -> DisplayFacts {
        DisplayFacts(
            id: 3, name: "ARZOPA", mirrorOf: master,
            modes: [DisplayMode(modeID: 1, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 60)],
            currentMode: DisplayMode(modeID: 1, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 60),
            widthMM: 344,
            ddc: .unavailable)
    }
}

final class ModePickerTests: XCTestCase {
    let modes = Fixtures.acerModes()

    func testNativeIsTheLargestNonHiDPIFramebuffer() throws {
        let native = try XCTUnwrap(ModePicker.nativePixelSize(modes))
        XCTAssertEqual(native.width, 3840)
        XCTAssertEqual(native.height, 2160)
    }

    func testBlurryLayoutsAreNotSharp() {
        let sharp = ModePicker.sharpLayouts(modes)
        XCTAssertFalse(sharp.contains(Layout(width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440)))
        XCTAssertFalse(sharp.contains(Layout(width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080)))
        XCTAssertTrue(sharp.contains(Layout(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880)))
        XCTAssertTrue(sharp.contains(Layout(width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160)))
    }

    func testRecommendedLayoutFor27Inch4KIs1440pHiDPI() throws {
        // 597 mm wide = 23.5 in: 2560 points ≈ 109 pt/in, the macOS ideal.
        let layout = try XCTUnwrap(ModePicker.recommendedLayout(modes, widthMM: 597))
        XCTAssertEqual(layout, Layout(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880))
    }

    func testWithoutPhysicalSizePreferExact2x() throws {
        let layout = try XCTUnwrap(ModePicker.recommendedLayout(modes, widthMM: nil))
        XCTAssertEqual(layout, Layout(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160))
    }

    func testHighestRefresh() throws {
        let layout = Layout(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880)
        let mode = try XCTUnwrap(ModePicker.bestMode(for: layout, in: modes, policy: .highest))
        XCTAssertEqual(mode.refreshRate, 160)
    }

    func testVideoFriendlyRefreshPrefers120() throws {
        let layout = Layout(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880)
        let mode = try XCTUnwrap(ModePicker.bestMode(for: layout, in: modes, policy: .videoFriendly))
        XCTAssertEqual(mode.refreshRate, 120)
    }

    func testFastLowResolutionModeFindsDFR() throws {
        let fast = try XCTUnwrap(ModePicker.fastLowResolutionMode(modes))
        XCTAssertEqual(fast.refreshRate, 320)
        XCTAssertEqual(fast.width, 1920)
    }

    func testMenuModesExcludeBlurryLayoutsButIncludeDFR() {
        let menu = ModePicker.menuModes(modes)
        XCTAssertFalse(menu.contains { $0.width == 2560 && !$0.isHiDPI })
        XCTAssertTrue(menu.contains { $0.refreshRate == 320 })
        XCTAssertFalse(menu.contains { $0.width == 1920 && !$0.isHiDPI && $0.refreshRate == 60 })
    }
}

final class KnowledgeBaseTests: XCTestCase {
    func testMatchesTheAcerByEDIDName() {
        XCTAssertEqual(KnowledgeBase.match(name: "XV272K V5", vendorID: 0x0472)?.id, "acer-xv272k-v5")
        XCTAssertEqual(KnowledgeBase.match(name: "Acer XV272K", vendorID: 0)?.id, "acer-xv272k-v5")
    }

    func testMatchesArzopa() {
        XCTAssertEqual(KnowledgeBase.match(name: "ARZOPA", vendorID: 0)?.id, "arzopa-portable")
    }

    func testUnknownMonitor() {
        XCTAssertNil(KnowledgeBase.match(name: "DELL U2723QE", vendorID: 0x10AC))
    }

    func testEveryCitedSourceExists() {
        for profile in KnowledgeBase.profiles {
            for step in profile.osd {
                for id in step.sourceIDs {
                    XCTAssertTrue(profile.source(id) != nil || KnowledgeBase.generalSource(id) != nil,
                                  "\(profile.id): missing source \(id)")
                }
            }
            for source in profile.sources {
                XCTAssertTrue(source.url.hasPrefix("https://"), source.url)
            }
        }
    }
}

final class EngineTests: XCTestCase {
    func context(_ displays: [DisplayFacts], lighting: RoomLighting = .normal, nightShift: Bool? = true) -> EngineContext {
        EngineContext(lighting: lighting, allDisplays: displays, nightShiftEnabled: nightShift, switchboardInstalled: true)
    }

    func change(_ id: String, in rec: Recommendation) -> PlannedChange? {
        rec.changes.first { $0.id == id }
    }

    func testCompetitiveGamingKeepsLayoutAndMaxesRefresh() throws {
        let acer = Fixtures.acer()
        let rec = RecommendationEngine.recommend(.competitiveGaming, for: acer, context: context([acer]))
        guard case .mode(let mode) = try XCTUnwrap(change("mode", in: rec)).change else { return XCTFail("no mode change") }
        XCTAssertEqual(mode.width, 2560)
        XCTAssertTrue(mode.isHiDPI)
        XCTAssertEqual(mode.refreshRate, 160)
        XCTAssertTrue(rec.manualSteps.contains { $0.setting == "Over Drive" && $0.value == "Normal" })
        XCTAssertTrue(rec.manualSteps.contains { $0.setting == "Refresh Rate" && $0.value.hasPrefix("Variable") })
        XCTAssertTrue(rec.notes.contains { $0.contains("320 Hz") })
        XCTAssertNil(change("night-shift", in: rec))
    }

    func testBlurryLayoutMovesToSharpOne() throws {
        let blurry = Fixtures.acerModes().first { $0.width == 2560 && !$0.isHiDPI && $0.refreshRate == 60 }
        let acer = Fixtures.acer(current: blurry)
        let rec = RecommendationEngine.recommend(.everyday, for: acer, context: context([acer]))
        guard case .mode(let mode) = try XCTUnwrap(change("mode", in: rec)).change else { return XCTFail("no mode change") }
        XCTAssertTrue(mode.isHiDPI)
        XCTAssertEqual(mode.width, 2560)
    }

    func testPhotoEditingUsesSRGBModeAndProfile() throws {
        let acer = Fixtures.acer()
        let rec = RecommendationEngine.recommend(.photoEditing, for: acer, context: context([acer]))

        guard case .colorProfile(let choice) = try XCTUnwrap(change("profile", in: rec)).change else { return XCTFail() }
        XCTAssertEqual(choice, .system(ProfileChoice.sRGBFile))
        XCTAssertTrue(rec.manualSteps.contains { $0.setting == "Mode" && $0.value == "sRGB" })

        // 120 cd/m² on a 400 cd/m² panel ≈ 30%.
        guard case .ddc(let brightness) = try XCTUnwrap(change("ddc-brightness", in: rec)).change else { return XCTFail() }
        XCTAssertEqual(brightness.value, .percent(30))

        guard case .ddc(let contrast) = try XCTUnwrap(change("ddc-contrast", in: rec)).change else { return XCTFail() }
        XCTAssertEqual(contrast.value, .percent(50))

        let nightShift = try XCTUnwrap(change("night-shift", in: rec))
        XCTAssertEqual(nightShift.change, .nightShift(enabled: false))
        XCTAssertTrue(rec.manualSteps.contains { $0.setting == "Switchboard brightness" })
    }

    func testDimRoomLowersEditingBrightness() throws {
        let acer = Fixtures.acer()
        let rec = RecommendationEngine.recommend(.photoEditing, for: acer, context: context([acer], lighting: .dim))
        guard case .ddc(let brightness) = try XCTUnwrap(change("ddc-brightness", in: rec)).change else { return XCTFail() }
        XCTAssertEqual(brightness.value, .percent(23)) // 90 / 400
    }

    func testVideoEditingPicks120Hz() throws {
        let acer = Fixtures.acer()
        let rec = RecommendationEngine.recommend(.videoEditing, for: acer, context: context([acer]))
        guard case .mode(let mode) = try XCTUnwrap(change("mode", in: rec)).change else { return XCTFail() }
        XCTAssertEqual(mode.refreshRate, 120)
    }

    func testGamingRestoresTheDisplaysOwnProfile() throws {
        let acer = Fixtures.acer(customProfile: "/System/Library/ColorSync/Profiles/sRGB Profile.icc")
        let rec = RecommendationEngine.recommend(.immersiveGaming, for: acer, context: context([acer]))
        guard case .colorProfile(let choice) = try XCTUnwrap(change("profile", in: rec)).change else { return XCTFail() }
        XCTAssertEqual(choice, .factory)
        XCTAssertTrue(rec.manualSteps.contains { $0.setting == "Mode" && $0.value.hasPrefix("Standard") })
    }

    func testMacBookLookIsBrightNativeGamutAndAccurate() throws {
        let acer = Fixtures.acer(customProfile: "/System/Library/ColorSync/Profiles/sRGB Profile.icc")
        let rec = RecommendationEngine.recommend(.macbookLook, for: acer, context: context([acer]))

        // The display's own profile (native wide gamut), not sRGB.
        guard case .colorProfile(let choice) = try XCTUnwrap(change("profile", in: rec)).change else { return XCTFail() }
        XCTAssertEqual(choice, .factory)
        XCTAssertTrue(rec.manualSteps.contains { $0.setting == "Mode" && $0.value.hasPrefix("Standard") })
        XCTAssertTrue(rec.manualSteps.contains { $0.setting == "Gamma" && $0.value == "2.2" })
        XCTAssertTrue(rec.manualSteps.contains { $0.setting == "High Dynamic Range" && $0.value == "Off" })

        // 350 cd/m² on a 400 cd/m² panel ≈ 88%; a bright room gets all of it.
        guard case .ddc(let brightness) = try XCTUnwrap(change("ddc-brightness", in: rec)).change else { return XCTFail() }
        XCTAssertEqual(brightness.value, .percent(88))
        let bright = RecommendationEngine.recommend(.macbookLook, for: acer, context: context([acer], lighting: .bright))
        guard case .ddc(let full) = try XCTUnwrap(change("ddc-brightness", in: bright)).change else { return XCTFail() }
        XCTAssertEqual(full.value, .percent(100))

        XCTAssertNotNil(change("night-shift", in: rec))
        XCTAssertTrue(rec.notes.contains { $0.contains("224 pixels per inch") })
    }

    func testCalibrationProfileIsLeftAlone() {
        let acer = Fixtures.acer(customProfile: "/Users/me/Library/ColorSync/Profiles/XV272K calibrated.icc")
        for useCase in UseCase.allCases {
            let rec = RecommendationEngine.recommend(useCase, for: acer, context: context([acer]))
            XCTAssertNil(change("profile", in: rec), "\(useCase)")
        }
    }

    func testMirroredArzopaIsNotGivenModeChangesAndWarnsGamers() {
        let acer = Fixtures.acer()
        let arzopa = Fixtures.arzopa()
        let all = [acer, arzopa]

        let arzopaRec = RecommendationEngine.recommend(.competitiveGaming, for: arzopa, context: context(all))
        XCTAssertNil(change("mode", in: arzopaRec))
        XCTAssertTrue(arzopaRec.notes.contains { $0.contains("Mirrors XV272K V5") })
        XCTAssertTrue(arzopaRec.changes.allSatisfy { if case .ddc = $0.change { return false }; return true })

        let acerRec = RecommendationEngine.recommend(.competitiveGaming, for: acer, context: context(all))
        XCTAssertTrue(acerRec.warnings.contains { $0.contains("ARZOPA") && $0.contains("Switchboard") })
    }

    func testNoDDCMeansNoHardwareChanges() {
        let acer = Fixtures.acer(ddc: .unavailable)
        let rec = RecommendationEngine.recommend(.photoEditing, for: acer, context: context([acer]))
        XCTAssertNil(change("ddc-brightness", in: rec))
        XCTAssertTrue(rec.notes.contains { $0.contains("DDC/CI") })
    }

    func testUnknownWideGamutMonitorGetsGenericAdvice() {
        var other = Fixtures.acer()
        other.name = "Some Monitor"
        other.vendorID = 0x1111
        other.ddc = .available([VCP.colorPreset: VCPValue(current: 2, max: 11), VCP.brightness: VCPValue(current: 50, max: 100)])
        let rec = RecommendationEngine.recommend(.photoEditing, for: other, context: context([other]))
        XCTAssertNil(rec.profile)
        XCTAssertNil(change("profile", in: rec)) // already on its own profile
        XCTAssertTrue(rec.warnings.contains { $0.contains("wide-gamut") })
        XCTAssertNil(change("ddc-preset", in: rec))
        XCTAssertTrue(rec.manualSteps.contains { $0.setting == "Picture mode" })
    }
}

final class DDCPacketTests: XCTestCase {
    func testSetPacket() {
        let packet = DDCPacket.withChecksum(DDCPacket.setVCPBody(0x10, value: 30))
        XCTAssertEqual(packet, [0x84, 0x03, 0x10, 0x00, 0x1E, 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x1E])
    }

    func testParseReply() {
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32]
        reply.append(reply.reduce(0x50, ^))
        XCTAssertEqual(DDCPacket.parseReply(reply, vcp: 0x10), VCPValue(current: 50, max: 100))
        reply[10] ^= 0xFF
        XCTAssertNil(DDCPacket.parseReply(reply, vcp: 0x10))
    }

    func testPercentScaling() {
        XCTAssertEqual(DDCTarget(vcp: 0x10, value: .percent(30)).rawValue(max: 100), 30)
        XCTAssertEqual(DDCTarget(vcp: 0x10, value: .percent(50)).rawValue(max: 255), 128)
        XCTAssertEqual(DDCTarget(vcp: 0x14, value: .raw(5)).rawValue(max: 11), 5)
    }
}

final class SnapshotTests: XCTestCase {
    func testOriginalsAreKept() {
        let a = Snapshot(displays: [DisplaySnapshot(key: "k", name: "A", mode: nil, hadCustomProfile: false,
                                                    customProfilePath: nil, ddc: [0x10: 80])],
                         nightShiftEnabled: true)
        let b = Snapshot(displays: [DisplaySnapshot(key: "k", name: "A", mode: nil, hadCustomProfile: true,
                                                    customProfilePath: "/x.icc", ddc: [0x10: 30, 0x12: 50])],
                         nightShiftEnabled: false)
        let merged = a.keepingOriginals(addingFrom: b)
        XCTAssertEqual(merged.display("k")?.ddc[0x10], 80)
        XCTAssertEqual(merged.display("k")?.ddc[0x12], 50)
        XCTAssertEqual(merged.display("k")?.hadCustomProfile, false)
        XCTAssertEqual(merged.nightShiftEnabled, true)
    }

    func testRoundTripsThroughJSON() throws {
        let snapshot = Snapshot(displays: [DisplaySnapshot(
            key: "k", name: "A",
            mode: DisplayMode(modeID: 3, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 160),
            hadCustomProfile: false, customProfilePath: nil, ddc: [0x10: 80])], nightShiftEnabled: nil)
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(Snapshot.self, from: data), snapshot)
    }
}
