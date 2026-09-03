import Foundation
import ImeTimeCore
import Testing
@testable import ImeTime

@MainActor
@Suite struct CreateRoomViewModelTests {
    @Test func emptyNameShowsErrorWithoutCallingRepository() async {
        let rooms = FakeRoomRepository()
        let sut = CreateRoomViewModel(rooms: rooms, timeZoneID: "Asia/Taipei")
        sut.nameInput = "  "
        #expect(await sut.create() == nil)
        #expect(sut.errorMessage == "請輸入名稱。")
        #expect(await rooms.createdRooms.isEmpty)
    }

    @Test func tooLongNameShowsLimit() async {
        let sut = CreateRoomViewModel(rooms: FakeRoomRepository(), timeZoneID: "Asia/Taipei")
        sut.nameInput = String(repeating: "字", count: 31)
        #expect(await sut.create() == nil)
        #expect(sut.errorMessage == "名稱最多 30 個字。")
    }

    @Test func createsWithTrimmedNameAndTimeZone() async {
        let rooms = FakeRoomRepository()
        let sut = CreateRoomViewModel(rooms: rooms, timeZoneID: "Asia/Taipei")
        sut.nameInput = " 週末小隊 "
        let room = await sut.create()
        #expect(room?.name == "週末小隊")
        let calls = await rooms.createdRooms
        #expect(calls.count == 1)
        #expect(calls.first?.name == "週末小隊")
        #expect(calls.first?.timeZoneID == "Asia/Taipei")
    }

    @Test func serverRoomErrorUsesItsMessage() async {
        let rooms = FakeRoomRepository()
        await rooms.fail(with: RoomError.invalidTimezone)
        let sut = CreateRoomViewModel(rooms: rooms, timeZoneID: "Nowhere/Land")
        sut.nameInput = "R"
        #expect(await sut.create() == nil)
        #expect(sut.errorMessage == RoomError.invalidTimezone.userMessage)
    }

    @Test func otherErrorsShowGenericMessage() async {
        let rooms = FakeRoomRepository()
        await rooms.fail(with: FakeError())
        let sut = CreateRoomViewModel(rooms: rooms, timeZoneID: "Asia/Taipei")
        sut.nameInput = "R"
        #expect(await sut.create() == nil)
        #expect(sut.errorMessage == "建立失敗，請檢查網路後再試一次。")
        #expect(sut.isSaving == false)
    }

    @Test func inviteShareTextContainsNameAndCode() {
        let room = FakeRoomRepository.makeRoom(name: "週末小隊", code: "ABCD23")
        let text = InviteShare.text(for: room)
        #expect(text.contains("週末小隊"))
        #expect(text.contains("ABCD23"))
    }
}
