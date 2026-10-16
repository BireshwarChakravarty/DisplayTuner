import Foundation

/// DDC/CI message bodies, checksums and reply parsing (from Switchboard).
///
/// On the wire every message is: destination 0x6E, source 0x51, then a body
/// whose first byte is 0x80 | (body length - 1), then a checksum. The
/// transport adds the address bytes; these helpers build body + checksum.
public enum DDCPacket {
    /// "Set VCP Feature": 0x84, opcode 0x03, vcp, value high, value low.
    public static func setVCPBody(_ vcp: UInt8, value: UInt16) -> [UInt8] {
        [0x84, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    /// "Get VCP Feature": 0x82, opcode 0x01, vcp.
    public static func getVCPBody(_ vcp: UInt8) -> [UInt8] {
        [0x82, 0x01, vcp]
    }

    /// Append the XOR checksum. The standard seed is 0x6E ^ 0x51 (both
    /// addresses); Apple Silicon read requests use 0x6E alone (see Arm64DDC).
    public static func withChecksum(_ body: [UInt8], seed: UInt8 = 0x6E ^ 0x51) -> [UInt8] {
        var checksum = seed
        for byte in body { checksum ^= byte }
        return body + [checksum]
    }

    /// Length of a "Get VCP Feature" reply.
    public static let replyLength = 11

    /// Parse a "Get VCP Feature" reply:
    ///   0x6E, 0x88, 0x02 (reply opcode), result (0 = ok), vcp, type,
    ///   max hi, max lo, current hi, current lo, checksum (seed 0x50).
    public static func parseReply(_ reply: [UInt8], vcp: UInt8) -> VCPValue? {
        guard reply.count >= replyLength,
              reply[2] == 0x02, reply[3] == 0x00, reply[4] == vcp else { return nil }
        var checksum: UInt8 = 0x50
        for byte in reply[0..<10] { checksum ^= byte }
        guard checksum == reply[10] else { return nil }
        let max = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard max > 0 else { return nil }
        // The colour preset is a code, not a level: its "max" isn't an upper
        // bound on the current value, so don't clamp it.
        let isCode = vcp == VCP.colorPreset
        return VCPValue(current: isCode ? current : Swift.min(current, max), max: max)
    }
}
