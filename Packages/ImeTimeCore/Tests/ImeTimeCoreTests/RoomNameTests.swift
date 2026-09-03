import Testing
@testable import ImeTimeCore

@Suite struct RoomNameTests {
    @Test func trimsAndAccepts30() throws {
        #expect(try RoomName("  週末小隊 ").value == "週末小隊")
        #expect(try RoomName(String(repeating: "字", count: 30)).value.count == 30)
    }

    @Test func rejectsEmptyAnd31() {
        #expect(throws: NameValidationError.empty) { try RoomName(" ") }
        #expect(throws: NameValidationError.tooLong(max: 30)) {
            try RoomName(String(repeating: "字", count: 31))
        }
    }
}
