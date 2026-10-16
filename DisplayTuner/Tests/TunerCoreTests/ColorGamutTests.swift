import XCTest
@testable import TunerCore

final class ColorGamutTests: XCTestCase {
    func testSRGBCoversItself() {
        XCTAssertEqual(Primaries.sRGB.coverage(of: .sRGB), 1, accuracy: 1e-9)
    }

    func testP3ContainsSRGB() {
        XCTAssertEqual(Primaries.displayP3.coverage(of: .sRGB), 1, accuracy: 1e-9)
    }

    func testSRGBCoversAboutThreeQuartersOfP3() {
        // Known figure: sRGB is ~73.6% of DCI-P3/Display P3 in CIE 1931 xy.
        XCTAssertEqual(Primaries.sRGB.coverage(of: .displayP3), 0.736, accuracy: 0.01)
    }

    func testWideGamutClassification() {
        XCTAssertFalse(Primaries.sRGB.isWideGamut)
        XCTAssertTrue(Primaries.displayP3.isWideGamut)
        XCTAssertTrue(Primaries.adobeRGB.isWideGamut)
    }

    func testCoverageIgnoresOrientation() {
        let reversed = Primaries(red: Primaries.sRGB.blue, green: Primaries.sRGB.green, blue: Primaries.sRGB.red)
        XCTAssertEqual(reversed.coverage(of: .displayP3), Primaries.sRGB.coverage(of: .displayP3), accuracy: 1e-9)
    }

    // MARK: ICC parsing

    /// sRGB's D50-adapted colorants, as stored in a v4 sRGB profile.
    let sRGBColorants: [[Double]] = [
        [0.4360747, 0.2225045, 0.0139322],
        [0.3850649, 0.7168786, 0.0971045],
        [0.1430804, 0.0606169, 0.7141733]
    ]

    /// Bradford D65 → D50.
    let bradfordD65toD50: [Double] = [
        1.0478112, 0.0228866, -0.0501270,
        0.0295424, 0.9904844, -0.0170491,
        -0.0092345, 0.0150436, 0.7521316
    ]

    func testPrimariesFromV4ProfileWithChad() throws {
        let data = ICCBuilder.make(colorants: sRGBColorants, white: [0.9642, 1.0, 0.8249],
                                   chad: bradfordD65toD50, description: "sRGB test")
        let primaries = try XCTUnwrap(ICCProfile.primaries(from: data))
        assertClose(primaries, .sRGB)
        let white = try XCTUnwrap(primaries.white)
        XCTAssertEqual(white.x, 0.3127, accuracy: 0.002)
        XCTAssertEqual(white.y, 0.3290, accuracy: 0.002)
    }

    func testPrimariesFromV2ProfileWithMediaWhite() throws {
        // No chad: undo the adaptation with Bradford from D50 to the media white.
        let data = ICCBuilder.make(colorants: sRGBColorants, white: [0.95047, 1.0, 1.08883], chad: nil, description: nil)
        let primaries = try XCTUnwrap(ICCProfile.primaries(from: data))
        assertClose(primaries, .sRGB)
    }

    func testDescriptionTag() {
        let data = ICCBuilder.make(colorants: sRGBColorants, white: [0.9642, 1.0, 0.8249], chad: nil, description: "XV272K V5")
        XCTAssertEqual(ICCProfile.description(from: data), "XV272K V5")
    }

    func testGarbageIsRejected() {
        XCTAssertNil(ICCProfile.primaries(from: Data(repeating: 0, count: 64)))
        XCTAssertNil(ICCProfile.primaries(from: Data(repeating: 0xFF, count: 400)))
    }

    private func assertClose(_ a: Primaries, _ b: Primaries, file: StaticString = #filePath, line: UInt = #line) {
        for (p, q) in [(a.red, b.red), (a.green, b.green), (a.blue, b.blue)] {
            XCTAssertEqual(p.x, q.x, accuracy: 0.003, file: file, line: line)
            XCTAssertEqual(p.y, q.y, accuracy: 0.003, file: file, line: line)
        }
    }
}

/// Builds minimal ICC display profiles for tests.
enum ICCBuilder {
    static func make(colorants: [[Double]], white: [Double], chad: [Double]?, description: String?) -> Data {
        var tags: [(String, [UInt8])] = [
            ("rXYZ", xyz(colorants[0])),
            ("gXYZ", xyz(colorants[1])),
            ("bXYZ", xyz(colorants[2])),
            ("wtpt", xyz(white))
        ]
        if let chad { tags.append(("chad", sf32(chad))) }
        if let description { tags.append(("desc", desc(description))) }

        var header = [UInt8](repeating: 0, count: 128)
        header.replaceSubrange(36..<40, with: Array("acsp".utf8))
        var table = be32(UInt32(tags.count))
        var body: [UInt8] = []
        var offset = 128 + 4 + tags.count * 12
        for (sig, data) in tags {
            table += Array(sig.utf8) + be32(UInt32(offset)) + be32(UInt32(data.count))
            body += data
            offset += data.count
        }
        return Data(header + table + body)
    }

    static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }

    static func fixed(_ v: Double) -> [UInt8] {
        be32(UInt32(bitPattern: Int32((v * 65536).rounded())))
    }

    static func xyz(_ v: [Double]) -> [UInt8] {
        Array("XYZ ".utf8) + [0, 0, 0, 0] + v.flatMap(fixed)
    }

    static func sf32(_ m: [Double]) -> [UInt8] {
        Array("sf32".utf8) + [0, 0, 0, 0] + m.flatMap(fixed)
    }

    static func desc(_ text: String) -> [UInt8] {
        let ascii = Array(text.utf8) + [0]
        return Array("desc".utf8) + [0, 0, 0, 0] + be32(UInt32(ascii.count)) + ascii
    }
}
