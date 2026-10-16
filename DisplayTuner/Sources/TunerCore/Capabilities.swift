import Foundation

/// What a monitor says it supports, from its DDC/CI capabilities string, e.g.
/// `(prot(monitor)type(lcd)model(XV272K V5)cmds(01 02 03 0C E3 F3)vcp(02 04 05 08 10 12 14(05 08 0B) 16 18 1A 60(0F 11 12) D6(01 04 05) DF)mccs_ver(2.2))`.
///
/// This replaces guessing: the app only offers a hardware change the monitor
/// itself lists.
public struct MonitorCapabilities: Hashable, Codable, Sendable {
    /// The string as the monitor sent it.
    public var raw: String
    public var model: String?
    public var mccsVersion: String?
    /// Supported VCP codes. Each maps to its allowed values; an empty list
    /// means the monitor didn't enumerate them (a continuous control).
    public var vcp: [UInt8: [UInt16]]

    public init(raw: String, model: String?, mccsVersion: String?, vcp: [UInt8: [UInt16]]) {
        self.raw = raw
        self.model = model
        self.mccsVersion = mccsVersion
        self.vcp = vcp
    }

    public func supports(_ code: UInt8) -> Bool { vcp[code] != nil }

    /// True only if the monitor explicitly lists `value` for `code`.
    public func supports(_ code: UInt8, value: UInt16) -> Bool { vcp[code]?.contains(value) ?? false }

    /// Colour presets (VCP 0x14) the monitor lists, by name.
    public var colorPresetNames: [String] {
        (vcp[VCP.colorPreset] ?? []).map(ColorPreset.name)
    }

    /// Supported controls worth showing a person, in a sensible order.
    public var describedControls: [String] {
        vcp.keys.sorted().compactMap { code in
            guard let name = VCP.knownNames[code] else { return nil }
            if code == VCP.colorPreset, !colorPresetNames.isEmpty {
                return "\(name) (\(colorPresetNames.joined(separator: ", ")))"
            }
            return name
        }
    }

    public static func parse(_ text: String) -> MonitorCapabilities? {
        let chars = Array(text)
        guard let vcpBody = section("vcp", in: chars) else { return nil }
        let codes = parseCodes(Array(vcpBody))
        guard !codes.isEmpty else { return nil }
        return MonitorCapabilities(
            raw: text,
            model: section("model", in: chars)?.trimmingCharacters(in: .whitespaces),
            mccsVersion: section("mccs_ver", in: chars)?.trimmingCharacters(in: .whitespaces),
            vcp: codes)
    }

    /// The contents of `name(...)`, honouring nested parentheses. A truncated
    /// string (missing closing brackets) yields what's there.
    static func section(_ name: String, in chars: [Character]) -> String? {
        let needle = name.lowercased() + "("
        let width = needle.count
        var i = 0
        while i + width <= chars.count {
            let boundary = i == 0 || !chars[i - 1].isLetter
            if boundary && String(chars[i..<(i + width)]).lowercased() == needle {
                var depth = 1
                var j = i + width
                let start = j
                while j < chars.count {
                    if chars[j] == "(" { depth += 1 }
                    if chars[j] == ")" { depth -= 1; if depth == 0 { break } }
                    j += 1
                }
                return String(chars[start..<j])
            }
            i += 1
        }
        return nil
    }

    /// Hex codes, each optionally followed by "(values)". Spaces between
    /// codes are optional: some monitors send "vcp(021012...)".
    static func parseCodes(_ chars: [Character]) -> [UInt8: [UInt16]] {
        var result: [UInt8: [UInt16]] = [:]
        var last: UInt8?
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isHexDigit, i + 1 < chars.count, chars[i + 1].isHexDigit,
               let code = UInt8(String(chars[i...(i + 1)]), radix: 16) {
                result[code] = result[code] ?? []
                last = code
                i += 2
            } else if c == "(" {
                var depth = 1
                var j = i + 1
                var values: [UInt16] = []
                while j < chars.count && depth > 0 {
                    if chars[j] == "(" { depth += 1 } else if chars[j] == ")" { depth -= 1 }
                    else if depth == 1, chars[j].isHexDigit, j + 1 < chars.count, chars[j + 1].isHexDigit,
                            let value = UInt16(String(chars[j...(j + 1)]), radix: 16) {
                        values.append(value)
                        j += 2
                        continue
                    }
                    j += 1
                }
                if let last { result[last] = values }
                i = j
            } else {
                i += 1
            }
        }
        return result
    }
}

extension DDCPacket {
    /// "Capabilities Request": 0x83, opcode 0xF3, offset high, offset low.
    public static func capabilitiesRequestBody(offset: UInt16) -> [UInt8] {
        [0x83, 0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF)]
    }

    /// The longest reply fragment: header, 32 data bytes, checksum.
    public static let capabilitiesReplyLength = 38

    /// Parse one "Capabilities Reply" fragment:
    ///   0x6E, 0x80 | length, 0xE3, offset high, offset low, data…, checksum
    /// where length counts the opcode, both offset bytes and the data.
    /// Returns the data (empty at the end of the string), or nil if the reply
    /// is malformed, for another offset, or fails its checksum.
    public static func parseCapabilitiesReply(_ reply: [UInt8], offset: UInt16) -> [UInt8]? {
        guard reply.count >= 6, reply[1] & 0x80 != 0 else { return nil }
        let length = Int(reply[1] & 0x7F)
        guard length >= 3, reply.count >= 3 + length, reply[2] == 0xE3,
              UInt16(reply[3]) << 8 | UInt16(reply[4]) == offset else { return nil }
        var checksum: UInt8 = 0x50
        for byte in reply[0..<(2 + length)] { checksum ^= byte }
        guard checksum == reply[2 + length] else { return nil }
        return Array(reply[5..<(2 + length)])
    }
}
