import Testing
@testable import ImeTimeCore

@Suite struct DisplayNameTests {
    @Test func trimsSurroundingWhitespace() throws {
        #expect(try DisplayName("  小明  ").value == "小明")
    }

    @Test func rejectsWhitespaceOnly() {
        #expect(throws: NameValidationError.empty) {
            try DisplayName("   \n")
        }
    }

    @Test func rejects21Characters() {
        #expect(throws: NameValidationError.tooLong(max: 20)) {
            try DisplayName(String(repeating: "字", count: 21))
        }
    }

    @Test func accepts20Characters() throws {
        let name = try DisplayName(String(repeating: "a", count: 20))
        #expect(name.value.count == 20)
    }

    @Test func countsGraphemeClustersNotBytes() throws {
        // 20 個 emoji（每個多 byte）仍是 20 個字
        let name = try DisplayName(String(repeating: "😀", count: 20))
        #expect(name.value.count == 20)
    }
}
