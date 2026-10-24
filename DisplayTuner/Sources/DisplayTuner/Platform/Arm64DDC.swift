// Adapted from Switchboard (github.com/BireshwarChakravarty/switchboard), MIT License,
// where it is proven on the Acer XV272K V5.
import Foundation
import IOKit
import CoreGraphics
import TunerCore

/// Everything the transport needs to find a monitor's DDC bus.
struct DisplayIdentity: Hashable {
    let id: CGDirectDisplayID
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let name: String

    init(id: CGDirectDisplayID, name: String) {
        self.id = id
        self.vendor = CGDisplayVendorNumber(id)
        self.model = CGDisplayModelNumber(id)
        self.serial = CGDisplaySerialNumber(id)
        self.name = name
    }
}

/// Apple-Silicon DDC/CI transport.
///
/// On Apple Silicon there is no public CGDisplayID → I2C bus mapping. The
/// working approach (shared by m1ddc and MonitorControl) is:
///   1. Walk the whole IOService plane in order.
///   2. Each framebuffer node (`AppleCLCD2` / `IOMobileFramebufferShim`)
///      carries the attached monitor's `EDID UUID` and `DisplayAttributes`.
///      Its DDC port is the next `DCPAVServiceProxy` node in the walk, so pair
///      each proxy with the framebuffer seen just before it.
///   3. Keep only proxies whose `Location` is `External`, and create an
///      `IOAVService` from each.
///   4. Score every candidate against the display's vendor/model/serial and
///      name, and use the best one.
///
/// Only ever used from AppModel's serial DDC queue.
final class Arm64DDC: @unchecked Sendable {

    private struct FramebufferInfo {
        var edidUUID = ""
        var productName: String?
        var vendor: UInt32?
        var model: UInt32?
        var serial: UInt32?
    }

    private struct AVCandidate {
        let service: IOAVService
        let info: FramebufferInfo
    }

    private var cache: [DisplayIdentity: IOAVService] = [:]
    /// When the last I2C transaction ended. DDC/CI asks for at least 50 ms
    /// after a write and between capabilities fragments (ddcutil quotes the
    /// spec in parms.h); shorter gaps make monitors drop commands.
    private var lastTransaction: UInt64 = 0
    private static let minimumGap: UInt64 = 50_000_000

    /// Wait until the bus has been quiet for `minimumGap`.
    private func pace() {
        let elapsed = DispatchTime.now().uptimeNanoseconds &- lastTransaction
        if elapsed < Self.minimumGap { usleep(useconds_t((Self.minimumGap - elapsed) / 1_000)) }
    }

    private func readReply(_ service: IOAVService, into reply: inout [UInt8]) -> IOReturn {
        defer { lastTransaction = DispatchTime.now().uptimeNanoseconds }
        return reply.withUnsafeMutableBytes { raw -> IOReturn in
            IOAVServiceReadI2C(service, 0x37, 0x51, raw.baseAddress!, UInt32(raw.count))
        }
    }

    func invalidate() { cache.removeAll() }

    /// Set a VCP feature. Returns true if the monitor acknowledged the write.
    func write(_ vcp: UInt8, value: UInt16, for display: DisplayIdentity) -> Bool {
        let packet = DDCPacket.withChecksum(DDCPacket.setVCPBody(vcp, value: value))

        if let cached = cache[display] {
            if send(packet, to: cached) { return true }
            cache[display] = nil // stale handle: look the display up again
        }
        guard let service = findService(for: display) else {
            Log.ddc.error("No DDC service matched \(display.name, privacy: .public) (display \(display.id))")
            return false
        }
        guard send(packet, to: service) else { return false }
        cache[display] = service
        return true
    }

    /// Read a VCP feature (current and maximum value), or nil if the monitor
    /// doesn't answer or doesn't support it.
    func read(_ vcp: UInt8, for display: DisplayIdentity) -> VCPValue? {
        guard let service = cache[display] ?? findService(for: display) else { return nil }
        let body = DDCPacket.getVCPBody(vcp)
        // m1ddc and MonitorControl seed a read request's checksum with 0x6E
        // alone on Apple Silicon; fall back to the standard seed if that
        // gets no valid reply.
        for seed: UInt8 in [0x6E, 0x6E ^ 0x51] {
            let request = DDCPacket.withChecksum(body, seed: seed)
            for _ in 0..<2 {
                guard send(request, to: service) else { continue }
                usleep(50_000) // monitors need time to prepare the reply
                var reply = [UInt8](repeating: 0, count: DDCPacket.replyLength)
                let result = readReply(service, into: &reply)
                if result == KERN_SUCCESS, let value = DDCPacket.parseReply(reply, vcp: vcp) {
                    cache[display] = service
                    return value
                }
                usleep(20_000)
            }
        }
        cache[display] = nil // retry with a fresh registry handle on the next read
        Log.ddc.notice("No reply reading VCP \(String(format: "0x%02X", vcp), privacy: .public) from \(display.name, privacy: .public)")
        return nil
    }

    /// The monitor's DDC/CI capabilities string: every control it supports and
    /// the values it accepts. Read in fragments of up to 32 bytes; nil if the
    /// monitor doesn't answer.
    func capabilities(for display: DisplayIdentity) -> String? {
        guard let service = cache[display] ?? findService(for: display) else { return nil }
        var text: [UInt8] = []
        var offset: UInt16 = 0
        var seeds: [UInt8] = [0x6E, 0x6E ^ 0x51]
        while offset < 2048 {
            var fragment: [UInt8]?
            attempts: for seed in seeds {
                let request = DDCPacket.withChecksum(DDCPacket.capabilitiesRequestBody(offset: offset), seed: seed)
                for _ in 0..<3 {
                    guard send(request, to: service) else { continue }
                    usleep(60_000) // MCCS allows the monitor 50 ms to prepare a reply
                    var reply = [UInt8](repeating: 0, count: DDCPacket.capabilitiesReplyLength)
                    let result = readReply(service, into: &reply)
                    if result == KERN_SUCCESS, let data = DDCPacket.parseCapabilitiesReply(reply, offset: offset) {
                        fragment = data
                        seeds = [seed] // this monitor's checksum convention; skip the other from now on
                        break attempts
                    }
                    usleep(30_000)
                }
            }
            guard let fragment else {
                // A partial list could hide supported values, so use none of it.
                Log.ddc.notice("Capabilities read stopped at offset \(offset) on \(display.name, privacy: .public)")
                return nil
            }
            if fragment.isEmpty { break }
            text += fragment
            if fragment.contains(0) { break }
            offset += UInt16(fragment.count)
        }
        let string = String(decoding: text.prefix { $0 != 0 }, as: UTF8.self)
        return string.isEmpty ? nil : string
    }

    /// The product name from the EDID, for displays NSScreen doesn't list
    /// (mirrors).
    func productName(for id: CGDirectDisplayID) -> String? {
        let display = DisplayIdentity(id: id, name: "")
        let best = collectCandidates()
            .map { ($0.info, score($0.info, against: display)) }
            .max(by: { $0.1 < $1.1 })
        guard let best, best.1 > 0, let name = best.0.productName, !name.isEmpty else { return nil }
        return name
    }

    // MARK: I2C write (chip 0x37, source offset 0x51)

    private func send(_ bytes: [UInt8], to service: IOAVService) -> Bool {
        // A couple of retries: DDC is a lossy, best-effort bus.
        for attempt in 0..<3 {
            pace()
            let result = bytes.withUnsafeBytes { raw -> IOReturn in
                IOAVServiceWriteI2C(service, 0x37, 0x51, raw.baseAddress!, UInt32(bytes.count))
            }
            lastTransaction = DispatchTime.now().uptimeNanoseconds
            if result == KERN_SUCCESS { return true }
            Log.ddc.debug("IOAVServiceWriteI2C attempt \(attempt) failed: \(result)")
        }
        return false
    }

    // MARK: DisplayIdentity → IOAVService

    private func findService(for display: DisplayIdentity) -> IOAVService? {
        // Identical serial-less displays cannot be safely mapped by model alone.
        let twins = DisplayDetector.onlineDisplayIDs().filter {
            CGDisplayVendorNumber($0) == display.vendor && CGDisplayModelNumber($0) == display.model
        }
        if twins.count > 1 && (display.serial == 0 || twins.contains(where: { $0 != display.id && CGDisplaySerialNumber($0) == display.serial })) { return nil }
        let candidates = collectCandidates()
        let scored = candidates.map { ($0, score($0.info, against: display)) }

        Log.ddc.info("Matching \(display.name, privacy: .public): vendor \(String(format: "%04X", display.vendor), privacy: .public) model \(String(format: "%04X", display.model), privacy: .public) serial \(display.serial)")
        for (candidate, score) in scored {
            Log.ddc.info("  candidate \(candidate.info.productName ?? "?", privacy: .public), EDID UUID \(candidate.info.edidUUID, privacy: .public), score \(score)")
        }

        let valid = scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        guard let best = valid.first, valid.count == 1 || best.1 > valid[1].1 else {
            Log.ddc.notice("DDC identity is missing or ambiguous; refusing access")
            return nil
        }
        return best.0.service
    }

    private func score(_ info: FramebufferInfo, against display: DisplayIdentity) -> Int {
        let uuid = info.edidUUID.uppercased()
        let vendor = info.vendor ?? (uuid.count >= 8 ? UInt32(uuid.prefix(4), radix: 16) : nil)
        let productHex = String(uuid.dropFirst(4).prefix(4))
        let model: UInt32? = info.model ?? (productHex.count == 4 ? UInt32(productHex.suffix(2) + productHex.prefix(2), radix: 16) : nil)
        return MonitorMatcher.score(
            targetVendor: display.vendor, targetModel: display.model, targetSerial: display.serial,
            candidateVendor: vendor, candidateModel: model, candidateSerial: info.serial)
    }

    /// Walk the IOService plane collecting external DDC services, each paired
    /// with the framebuffer (and so the monitor) that precedes it.
    private func collectCandidates() -> [AVCandidate] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }

        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(
            root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        let nameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_name_t>.size)
        defer { nameBuffer.deallocate() }

        var candidates: [AVCandidate] = []
        var lastFramebuffer: FramebufferInfo?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard IORegistryEntryGetName(entry, nameBuffer) == KERN_SUCCESS else { continue }
            let name = String(cString: nameBuffer)

            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                lastFramebuffer = framebufferInfo(entry)
            } else if name.contains("DCPAVServiceProxy") {
                guard copyProperty("Location", of: entry) as? String == "External",
                      let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)
                else { continue }
                candidates.append(AVCandidate(service: service, info: lastFramebuffer ?? FramebufferInfo()))
                lastFramebuffer = nil
            }
        }
        return candidates
    }

    private func framebufferInfo(_ entry: io_registry_entry_t) -> FramebufferInfo {
        var info = FramebufferInfo()
        info.edidUUID = copyProperty("EDID UUID", of: entry) as? String ?? ""
        if let attrs = copyProperty("DisplayAttributes", of: entry) as? [String: Any],
           let product = attrs["ProductAttributes"] as? [String: Any] {
            info.productName = product["ProductName"] as? String
            info.vendor = (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value
            info.model = (product["ProductID"] as? NSNumber)?.uint32Value
            info.serial = (product["SerialNumber"] as? NSNumber)?.uint32Value
        }
        return info
    }

    private func copyProperty(_ key: String, of entry: io_registry_entry_t) -> Any? {
        guard let ref = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0
        ) else { return nil }
        return ref.takeRetainedValue()
    }
}
