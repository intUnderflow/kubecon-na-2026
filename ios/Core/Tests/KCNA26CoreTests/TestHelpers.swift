import XCTest

/// Shared assertion helpers for Kotlin-test idioms (owner: foundation / integration). Use these
/// instead of declaring a private copy in a test file: a private extension member with the same
/// signature as one here is an invalid redeclaration.
extension Array {
    /// Kotlin `single { }`: the one element matching; throws (failing the test) otherwise.
    func singleMatch(file: StaticString = #filePath, line: UInt = #line, _ predicate: (Element) -> Bool) throws -> Element {
        let xs = filter(predicate)
        return try XCTUnwrap(xs.count == 1 ? xs[0] : nil, "single: \(xs.count) matches", file: file, line: line)
    }
}
