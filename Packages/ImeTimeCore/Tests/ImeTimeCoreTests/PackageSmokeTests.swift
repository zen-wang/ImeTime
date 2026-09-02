import Testing
@testable import ImeTimeCore

@Suite struct PackageSmokeTests {
    @Test func versionIsSet() {
        #expect(ImeTimeCore.version == "0.1.0")
    }
}
