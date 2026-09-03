import Foundation
import ImeTimeCore
import Testing
@testable import ImeTime

@MainActor
@Suite struct JoinRoomViewModelTests {
    @Test func canSubmitOnlyWhenSixValidCharacters() {
        let sut = JoinRoomViewModel(rooms: FakeRoomRepository())
        sut.codeInput = "ABCD2"
        #expect(sut.canSubmit == false)
        sut.codeInput = "abcd23"
        #expect(sut.canSubmit == true)
        sut.codeInput = "ABCDE0"
        #expect(sut.canSubmit == false)
    }

    @Test func malformedCodeShowsFormatErrorWithoutCallingRepository() async {
        let rooms = FakeRoomRepository()
        let sut = JoinRoomViewModel(rooms: rooms)
        sut.codeInput = "ABC"
        #expect(await sut.join() == nil)
        #expect(sut.errorMessage == "邀請碼是 6 個字母或數字。")
        #expect(await rooms.joinedCodes.isEmpty)
    }

    @Test func joinsWithNormalizedCode() async {
        let rooms = FakeRoomRepository()
        let sut = JoinRoomViewModel(rooms: rooms)
        sut.codeInput = " ab-cd 23 "
        let room = await sut.join()
        #expect(room?.inviteCode == "ABCD23")
        #expect(await rooms.joinedCodes == ["ABCD23"])
    }

    @Test func roomErrorsShowTheirMessages() async {
        for expected in [RoomError.invalidCode, .roomFull, .alreadyMember, .rateLimited] {
            let rooms = FakeRoomRepository()
            await rooms.failJoin(with: expected)
            let sut = JoinRoomViewModel(rooms: rooms)
            sut.codeInput = "ABCD23"
            #expect(await sut.join() == nil)
            #expect(sut.errorMessage == expected.userMessage)
        }
    }

    @Test func otherErrorsShowGenericMessage() async {
        let rooms = FakeRoomRepository()
        await rooms.fail(with: FakeError())
        let sut = JoinRoomViewModel(rooms: rooms)
        sut.codeInput = "ABCD23"
        #expect(await sut.join() == nil)
        #expect(sut.errorMessage == "加入失敗，請檢查網路後再試一次。")
        #expect(sut.isJoining == false)
    }
}
