import Testing
@testable import ImeTimeCore

@Suite struct RoomErrorTests {
    @Test func mapsKnownServerMessages() {
        #expect(RoomError(serverMessage: "invalid_code") == .invalidCode)
        #expect(RoomError(serverMessage: "room_full") == .roomFull)
        #expect(RoomError(serverMessage: "already_member") == .alreadyMember)
        #expect(RoomError(serverMessage: "rate_limited") == .rateLimited)
        #expect(RoomError(serverMessage: "not_member") == .notMember)
        #expect(RoomError(serverMessage: "invalid_name") == .invalidName)
        #expect(RoomError(serverMessage: "invalid_timezone") == .invalidTimezone)
        #expect(RoomError(serverMessage: "profile_required") == .profileRequired)
        #expect(RoomError(serverMessage: "not_authenticated") == .notAuthenticated)
    }

    @Test func keepsUnknownMessage() {
        #expect(RoomError(serverMessage: "boom") == .unknown("boom"))
    }

    @Test func everyCaseHasNonEmptyUserMessage() {
        let all: [RoomError] = [.invalidCode, .roomFull, .alreadyMember, .rateLimited, .notMember,
                                .invalidName, .invalidTimezone, .profileRequired, .notAuthenticated, .unknown("x")]
        for error in all {
            #expect(!error.userMessage.isEmpty)
        }
    }
}
