import Foundation

/// Fail closed: a manufacturer alone never identifies a monitor. Equal scores
/// must be rejected by the caller, especially for identical serial-less panels.
public enum MonitorMatcher {
    public static func score(targetVendor: UInt32, targetModel: UInt32, targetSerial: UInt32,
                             candidateVendor: UInt32?, candidateModel: UInt32?, candidateSerial: UInt32?) -> Int {
        guard targetVendor != 0, targetModel != 0,
              candidateVendor == targetVendor, candidateModel == targetModel else { return 0 }
        if targetSerial != 0, let serial = candidateSerial, serial != 0 {
            return serial == targetSerial ? 10 : 0
        }
        return 4
    }
}
