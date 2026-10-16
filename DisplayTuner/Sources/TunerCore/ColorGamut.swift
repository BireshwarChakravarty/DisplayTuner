import Foundation

/// A CIE 1931 xy chromaticity.
public struct XY: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// The red, green and blue primaries of a colour space or a display.
public struct Primaries: Hashable, Codable, Sendable {
    public var red: XY
    public var green: XY
    public var blue: XY
    public var white: XY?

    public init(red: XY, green: XY, blue: XY, white: XY? = nil) {
        self.red = red
        self.green = green
        self.blue = blue
        self.white = white
    }

    public static let sRGB = Primaries(
        red: XY(0.640, 0.330), green: XY(0.300, 0.600), blue: XY(0.150, 0.060), white: XY(0.3127, 0.3290))
    public static let displayP3 = Primaries(
        red: XY(0.680, 0.320), green: XY(0.265, 0.690), blue: XY(0.150, 0.060), white: XY(0.3127, 0.3290))
    public static let adobeRGB = Primaries(
        red: XY(0.640, 0.330), green: XY(0.210, 0.710), blue: XY(0.150, 0.060), white: XY(0.3127, 0.3290))

    var triangle: [XY] { [red, green, blue] }

    /// Area of the gamut triangle in the xy diagram.
    public var area: Double { Geometry.area(triangle) }

    /// Fraction (0...1) of `target`'s xy triangle that this gamut covers.
    /// "Covers 95% of DCI-P3" in reviews means `coverage(of: .displayP3) == 0.95`.
    public func coverage(of target: Primaries) -> Double {
        let targetArea = target.area
        guard targetArea > 0 else { return 0 }
        let overlap = Geometry.clip(target.triangle, to: triangle)
        return min(1, Geometry.area(overlap) / targetArea)
    }

    /// Wide gamut = clearly beyond sRGB (most "90% DCI-P3" monitors land here).
    public var isWideGamut: Bool {
        coverage(of: .displayP3) >= 0.85 || area / Primaries.sRGB.area >= 1.15
    }
}

enum Geometry {
    /// Shoelace formula.
    static func area(_ polygon: [XY]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        var sum = 0.0
        for i in polygon.indices {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Sutherland–Hodgman: the part of `subject` inside the convex polygon `clip`.
    static func clip(_ subject: [XY], to clip: [XY]) -> [XY] {
        guard clip.count >= 3 else { return [] }
        // Make the clip polygon counter-clockwise so "inside" is "left of each edge".
        let ccw = signedArea(clip) >= 0 ? clip : clip.reversed()
        var output = subject
        for i in ccw.indices {
            let a = ccw[i]
            let b = ccw[(i + 1) % ccw.count]
            let input = output
            output = []
            guard !input.isEmpty else { break }
            for j in input.indices {
                let p = input[j]
                let q = input[(j + 1) % input.count]
                let pIn = cross(a, b, p) >= -1e-12
                let qIn = cross(a, b, q) >= -1e-12
                if pIn { output.append(p) }
                if pIn != qIn, let x = intersection(p, q, a, b) { output.append(x) }
            }
        }
        return output
    }

    private static func signedArea(_ polygon: [XY]) -> Double {
        var sum = 0.0
        for i in polygon.indices {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    private static func cross(_ a: XY, _ b: XY, _ p: XY) -> Double {
        (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
    }

    private static func intersection(_ p: XY, _ q: XY, _ a: XY, _ b: XY) -> XY? {
        let d = (p.x - q.x) * (a.y - b.y) - (p.y - q.y) * (a.x - b.x)
        guard abs(d) > 1e-15 else { return nil }
        let t = ((p.x - a.x) * (a.y - b.y) - (p.y - a.y) * (a.x - b.x)) / d
        return XY(p.x + t * (q.x - p.x), p.y + t * (q.y - p.y))
    }
}

// MARK: - ICC profiles

/// Reads the primaries out of an ICC display profile (the `rXYZ`/`gXYZ`/`bXYZ`
/// colorant tags), undoing the profile's chromatic adaptation so the result is
/// the panel's real primaries rather than their D50-adapted values.
///
/// For a monitor that hasn't been calibrated, macOS builds the profile from the
/// monitor's EDID, so this is what the manufacturer says about the panel.
public enum ICCProfile {
    public static func primaries(from data: Data) -> Primaries? {
        let reader = Reader(bytes: [UInt8](data))
        guard let tags = reader.tagTable() else { return nil }

        guard let r = reader.xyz(at: tags["rXYZ"]),
              let g = reader.xyz(at: tags["gXYZ"]),
              let b = reader.xyz(at: tags["bXYZ"]) else { return nil }

        // Colorants are stored adapted to the D50 connection space. Undo it with
        // the profile's own adaptation matrix (v4, and most modern v2), or
        // else with Bradford from D50 to the profile's media white point (v2).
        let undo: Matrix3
        let white: Vec3
        if let chad = reader.matrix(at: tags["chad"]), let inverse = chad.inverse {
            undo = inverse
            white = inverse * Vec3.d50
        } else {
            let mediaWhite = reader.xyz(at: tags["wtpt"]) ?? Vec3.d50
            undo = Matrix3.bradford(from: Vec3.d50, to: mediaWhite)
            white = mediaWhite
        }

        guard let red = (undo * r).chromaticity,
              let green = (undo * g).chromaticity,
              let blue = (undo * b).chromaticity else { return nil }
        return Primaries(red: red, green: green, blue: blue, white: white.chromaticity)
    }

    /// The profile's description (`desc` tag), e.g. "XV272K V5" or "sRGB IEC61966-2.1".
    public static func description(from data: Data) -> String? {
        let reader = Reader(bytes: [UInt8](data))
        guard let tags = reader.tagTable(), let offset = tags["desc"] else { return nil }
        return reader.text(at: offset)
    }

    private struct Reader {
        let bytes: [UInt8]

        func u32(_ o: Int) -> UInt32? {
            guard o >= 0, o + 4 <= bytes.count else { return nil }
            return UInt32(bytes[o]) << 24 | UInt32(bytes[o + 1]) << 16 | UInt32(bytes[o + 2]) << 8 | UInt32(bytes[o + 3])
        }

        func u16(_ o: Int) -> UInt16? {
            guard o >= 0, o + 2 <= bytes.count else { return nil }
            return UInt16(bytes[o]) << 8 | UInt16(bytes[o + 1])
        }

        func s15Fixed16(_ o: Int) -> Double? {
            guard let v = u32(o) else { return nil }
            return Double(Int32(bitPattern: v)) / 65536
        }

        func signature(_ o: Int) -> String? {
            guard o >= 0, o + 4 <= bytes.count else { return nil }
            return String(bytes: bytes[o..<o + 4], encoding: .ascii)
        }

        func tagTable() -> [String: Int]? {
            guard bytes.count >= 132, signature(36) == "acsp", let count = u32(128), count < 200 else { return nil }
            var tags: [String: Int] = [:]
            for i in 0..<Int(count) {
                let entry = 132 + i * 12
                guard let sig = signature(entry), let offset = u32(entry + 4) else { return nil }
                tags[sig] = Int(offset)
            }
            return tags
        }

        func xyz(at offset: Int?) -> Vec3? {
            guard let o = offset, signature(o) == "XYZ ",
                  let x = s15Fixed16(o + 8), let y = s15Fixed16(o + 12), let z = s15Fixed16(o + 16) else { return nil }
            return Vec3(x, y, z)
        }

        func matrix(at offset: Int?) -> Matrix3? {
            guard let o = offset, signature(o) == "sf32" else { return nil }
            var values: [Double] = []
            for i in 0..<9 {
                guard let v = s15Fixed16(o + 8 + i * 4) else { return nil }
                values.append(v)
            }
            return Matrix3(rows: [
                Vec3(values[0], values[1], values[2]),
                Vec3(values[3], values[4], values[5]),
                Vec3(values[6], values[7], values[8])
            ])
        }

        func text(at o: Int) -> String? {
            switch signature(o) {
            case "desc": // v2: length-prefixed ASCII
                guard let length = u32(o + 8), length > 0, o + 12 + Int(length) <= bytes.count else { return nil }
                let raw = bytes[(o + 12)..<(o + 12 + Int(length))].prefix { $0 != 0 }
                return String(bytes: raw, encoding: .ascii)
            case "mluc": // v4: first record, UTF-16BE
                guard let records = u32(o + 8), records > 0,
                      let length = u32(o + 20), let start = u32(o + 24) else { return nil }
                let begin = o + Int(start)
                guard begin + Int(length) <= bytes.count else { return nil }
                var units: [UInt16] = []
                var i = begin
                while i + 1 < begin + Int(length) {
                    if let unit = u16(i) { units.append(unit) }
                    i += 2
                }
                return String(decoding: units, as: UTF16.self)
            default:
                return nil
            }
        }
    }
}

// MARK: - Small linear algebra

struct Vec3: Equatable {
    var x: Double, y: Double, z: Double
    init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }

    static let d50 = Vec3(0.9642, 1.0, 0.8249)
    static let d65 = Vec3(0.95047, 1.0, 1.08883)

    var chromaticity: XY? {
        let sum = x + y + z
        guard sum > 1e-9 else { return nil }
        return XY(x / sum, y / sum)
    }
}

struct Matrix3 {
    var rows: [Vec3]

    static func * (m: Matrix3, v: Vec3) -> Vec3 {
        Vec3(
            m.rows[0].x * v.x + m.rows[0].y * v.y + m.rows[0].z * v.z,
            m.rows[1].x * v.x + m.rows[1].y * v.y + m.rows[1].z * v.z,
            m.rows[2].x * v.x + m.rows[2].y * v.y + m.rows[2].z * v.z
        )
    }

    static func * (a: Matrix3, b: Matrix3) -> Matrix3 {
        let columns = [Vec3(b.rows[0].x, b.rows[1].x, b.rows[2].x),
                       Vec3(b.rows[0].y, b.rows[1].y, b.rows[2].y),
                       Vec3(b.rows[0].z, b.rows[1].z, b.rows[2].z)]
        let products = columns.map { a * $0 }
        return Matrix3(rows: [
            Vec3(products[0].x, products[1].x, products[2].x),
            Vec3(products[0].y, products[1].y, products[2].y),
            Vec3(products[0].z, products[1].z, products[2].z)
        ])
    }

    var inverse: Matrix3? {
        let a = rows[0], b = rows[1], c = rows[2]
        let det = a.x * (b.y * c.z - b.z * c.y) - a.y * (b.x * c.z - b.z * c.x) + a.z * (b.x * c.y - b.y * c.x)
        guard abs(det) > 1e-12 else { return nil }
        let k = 1 / det
        return Matrix3(rows: [
            Vec3((b.y * c.z - b.z * c.y) * k, (a.z * c.y - a.y * c.z) * k, (a.y * b.z - a.z * b.y) * k),
            Vec3((b.z * c.x - b.x * c.z) * k, (a.x * c.z - a.z * c.x) * k, (a.z * b.x - a.x * b.z) * k),
            Vec3((b.x * c.y - b.y * c.x) * k, (a.y * c.x - a.x * c.y) * k, (a.x * b.y - a.y * b.x) * k)
        ])
    }

    static let bradfordCone = Matrix3(rows: [
        Vec3(0.8951, 0.2664, -0.1614),
        Vec3(-0.7502, 1.7135, 0.0367),
        Vec3(0.0389, -0.0685, 1.0296)
    ])

    /// Bradford chromatic adaptation from one white point to another.
    static func bradford(from source: Vec3, to destination: Vec3) -> Matrix3 {
        let cone = bradfordCone
        guard let coneInverse = cone.inverse else { return Matrix3(rows: [Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1)]) }
        let s = cone * source
        let d = cone * destination
        let scale = Matrix3(rows: [Vec3(d.x / s.x, 0, 0), Vec3(0, d.y / s.y, 0), Vec3(0, 0, d.z / s.z)])
        return coneInverse * (scale * cone)
    }
}
