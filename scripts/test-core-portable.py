#!/usr/bin/env python3
"""Run the core regression suite on Command Line Tools installations without XCTest.

The same test method bodies run in CI using XCTest. This small assertion adapter
keeps local safety validation possible without requiring a full Xcode install.
"""
from pathlib import Path
import os, re, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='displaytuner-tests-') as directory:
    out = Path(directory)
    shim = r'''
import Foundation
class XCTestCase {}
var failures = 0
var checks = 0
func XCTFail(_ message: String = "Failure", file: StaticString = #filePath, line: UInt = #line) {
    failures += 1; print("FAIL \(file):\(line): \(message)")
}
func XCTAssertTrue(_ value: @autoclosure () -> Bool, _ message: String = "Expected true", file: StaticString = #filePath, line: UInt = #line) {
    checks += 1; if !value() { XCTFail(message, file: file, line: line) }
}
func XCTAssertFalse(_ value: @autoclosure () -> Bool, _ message: String = "Expected false", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(!value(), message, file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "Values differ", file: StaticString = #filePath, line: UInt = #line) {
    checks += 1; if a != b { XCTFail("\(message): \(a) != \(b)", file: file, line: line) }
}
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    checks += 1; if abs(a-b) > accuracy { XCTFail("\(a) != \(b) ± \(accuracy)", file: file, line: line) }
}
func XCTAssertNil<T>(_ value: T?, _ message: String = "Expected nil", file: StaticString = #filePath, line: UInt = #line) {
    checks += 1; if value != nil { XCTFail(message, file: file, line: line) }
}
func XCTAssertNotNil<T>(_ value: T?, _ message: String = "Expected non-nil", file: StaticString = #filePath, line: UInt = #line) {
    checks += 1; if value == nil { XCTFail(message, file: file, line: line) }
}
struct UnwrapError: Error {}
func XCTUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    checks += 1; guard let value else { XCTFail("Expected non-nil", file: file, line: line); throw UnwrapError() }; return value
}
'''
    (out/'Assertions.swift').write_text(shim)
    tests = []
    calls = []
    for source in sorted((root/'DisplayTuner/Tests/TunerCoreTests').glob('*.swift')):
        body = source.read_text().replace('import XCTest','import Foundation').replace('@testable import TunerCore','')
        path = out/source.name; path.write_text(body); tests.append(str(path))
        current = None
        for line in body.splitlines():
            if match := re.match(r'final class (\w+): XCTestCase', line): current = match[1]
            if match := re.match(r'    func (test\w+)\(\)( throws)?', line):
                name = f'{current}().{match[1]}()'
                calls.append(f'do {{ try {name} }} catch {{ XCTFail("{name}: \\(error)") }}' if match[2] else name)
    main = 'import Foundation\n' + '\n'.join(calls) + f'\nprint("{len(calls)} tests, \\(checks) assertions, \\(failures) failures")\nexit(failures == 0 ? 0 : 1)\n'
    (out/'main.swift').write_text(main)
    sources = [str(p) for p in (root/'DisplayTuner/Sources/TunerCore').glob('*.swift')]
    environment = os.environ.copy(); environment['CLANG_MODULE_CACHE_PATH'] = str(out/'cache')
    subprocess.run(['swiftc', '-module-cache-path',str(out/'cache'), *sources, str(out/'Assertions.swift'), *tests, str(out/'main.swift'), '-o', str(out/'tests')], check=True, env=environment)
    subprocess.run([str(out/'tests')], check=True)
