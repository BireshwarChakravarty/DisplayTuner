import XCTest
@testable import TunerCore

final class SafetyTests: XCTestCase {
    func testVendorAloneNeverMatches() {
        XCTAssertEqual(MonitorMatcher.score(targetVendor: 1, targetModel: 2, targetSerial: 3, candidateVendor: 1, candidateModel: 9, candidateSerial: nil), 0)
        XCTAssertEqual(MonitorMatcher.score(targetVendor: 1, targetModel: 2, targetSerial: 3, candidateVendor: 1, candidateModel: nil, candidateSerial: nil), 0)
    }
    func testConflictingSerialIsRejected() {
        XCTAssertEqual(MonitorMatcher.score(targetVendor: 1, targetModel: 2, targetSerial: 3, candidateVendor: 1, candidateModel: 2, candidateSerial: 4), 0)
    }
    func testExactSerialOutranksModelOnly() {
        let exact = MonitorMatcher.score(targetVendor: 1, targetModel: 2, targetSerial: 3, candidateVendor: 1, candidateModel: 2, candidateSerial: 3)
        let generic = MonitorMatcher.score(targetVendor: 1, targetModel: 2, targetSerial: 3, candidateVendor: 1, candidateModel: 2, candidateSerial: nil)
        XCTAssertTrue(exact > generic)
        XCTAssertTrue(generic > 0)
    }
    func testUnknownIdentitiesAreRejected() {
        XCTAssertEqual(MonitorMatcher.score(targetVendor: 0, targetModel: 0, targetSerial: 0, candidateVendor: 0, candidateModel: 0, candidateSerial: 0), 0)
    }
    func testCalibrationProtectsHardwareAndMonitorMenu() {
        let display = Fixtures.acer(customProfile: "/Users/example/Library/ColorSync/Profiles/Measured.icc")
        for useCase in UseCase.allCases {
            let rec = RecommendationEngine.recommend(useCase, for: display, context: EngineContext(lighting: .normal, allDisplays: [display]))
            XCTAssertFalse(rec.changes.contains { if case .ddc = $0.change { return true }; return false })
            XCTAssertFalse(rec.changes.contains { if case .colorProfile = $0.change { return true }; return false })
            XCTAssertFalse(rec.manualSteps.contains { $0.place == .monitorMenu })
        }
    }
    func testSeriallessDisplayKeysDoNotCollide() {
        let a = DisplayFacts(id: 1, name: "Monitor", vendorID: 1, productID: 2)
        let b = DisplayFacts(id: 2, name: "Monitor", vendorID: 1, productID: 2)
        XCTAssertFalse(a.key == b.key)
    }
    func testPersistentIdentitySurvivesReconnection() {
        let a = DisplayFacts(id: 1, name: "Monitor", persistentID: "display-uuid")
        let b = DisplayFacts(id: 2, name: "Monitor", persistentID: "display-uuid")
        XCTAssertEqual(a.key, b.key)
    }
    func testProfileOriginalIsCapturedWhenFirstChangedLater() {
        let first = Snapshot(displays: [DisplaySnapshot(key: "a", name: "A", mode: nil, hadCustomProfile: false, customProfilePath: nil, ddc: [0x10: 50], capturesProfile: false)], nightShiftEnabled: nil)
        let later = Snapshot(displays: [DisplaySnapshot(key: "a", name: "A", mode: nil, hadCustomProfile: true, customProfilePath: "/measured.icc", ddc: [:], capturesProfile: true)], nightShiftEnabled: nil)
        let merged = first.keepingOriginals(addingFrom: later)
        XCTAssertEqual(merged.display("a")?.customProfilePath, "/measured.icc")
        XCTAssertEqual(merged.display("a")?.capturesProfile, true)
        XCTAssertEqual(merged.display("a")?.ddc[0x10], 50)
    }
    func testLegacySnapshotDecoding() throws {
        let old = #"{"key":"a","name":"A","hadCustomProfile":false,"ddc":[16,50]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DisplaySnapshot.self, from: old)
        XCTAssertTrue(decoded.capturesProfile)
        XCTAssertEqual(decoded.ddc[16], 50)
    }
    func testPercentTargetsClampToHardwareRange() {
        XCTAssertEqual(DDCTarget(vcp: 16, value: .percent(-20)).rawValue(max: 255), 0)
        XCTAssertEqual(DDCTarget(vcp: 16, value: .percent(200)).rawValue(max: 255), 255)
    }
}
