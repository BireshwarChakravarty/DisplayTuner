// From Switchboard (github.com/BireshwarChakravarty/switchboard), MIT License.
import Foundation
import IOKit

// MARK: - Private IOKit symbols (Apple Silicon DDC over I2C)
//
// These three symbols ship inside IOKit.framework on Apple Silicon Macs but are
// not declared in any public header. They are the same symbols m1ddc and
// MonitorControl use to talk DDC/CI to external displays. We bind them by name
// with @_silgen_name so the linker resolves them from IOKit at launch.
//
// IOAVService is an opaque CoreFoundation type.
typealias IOAVService = CFTypeRef

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(
    _ allocator: CFAllocator?,
    _ service: io_service_t
) -> IOAVService?

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(
    _ service: IOAVService,
    _ chipAddress: UInt32,
    _ offset: UInt32,
    _ inputBuffer: UnsafeRawPointer,
    _ inputBufferSize: UInt32
) -> IOReturn

@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(
    _ service: IOAVService,
    _ chipAddress: UInt32,
    _ offset: UInt32,
    _ outputBuffer: UnsafeMutableRawPointer,
    _ outputBufferSize: UInt32
) -> IOReturn
