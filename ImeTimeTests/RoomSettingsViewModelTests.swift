import Foundation
import ImeTimeCore
import Testing
@testable import ImeTime

@MainActor
@Suite struct RoomSettingsViewModelTests {
    let me = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let other = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func member(_ id: UUID, role: RoomMember.Role, muted: Bool = false, in room: Room) -> RoomMember {
        RoomMember(roomID: room.id, userID: id, role: role, notificationsMuted: muted, joinedAt: Date(),
                   profile: Profile(id: id, displayName: id == me ? "我" : "朋友", avatarPath: nil, createdAt: Date()))
    }

    private func makeSUT(myRole: RoomMember.Role, muted: Bool = false) async -> (RoomSettingsViewModel, FakeRoomRepository, Room) {
        let room = FakeRoomRepository.makeRoom(createdBy: me)
        let rooms = FakeRoomRepository()
        await rooms.set(members: [member(me, role: myRole, muted: muted, in: room),
                                  member(other, role: myRole == .owner ? .member : .owner, in: room)], for: room.id)
        let sut = RoomSettingsViewModel(room: room, currentUserID: me, rooms: rooms)
        await sut.load()
        return (sut, rooms, room)
    }

    @Test func loadsMembersAndDerivesOwnership() async {
        let (sut, _, _) = await makeSUT(myRole: .owner)
        #expect(sut.members.count == 2)
        #expect(sut.isOwner == true)
        #expect(sut.isMuted == false)
    }

    @Test func memberIsNotOwner() async {
        let (sut, _, _) = await makeSUT(myRole: .member, muted: true)
        #expect(sut.isOwner == false)
        #expect(sut.isMuted == true)
    }

    @Test func ownerRemovesOtherMember() async {
        let (sut, rooms, room) = await makeSUT(myRole: .owner)
        let target = sut.members.first { $0.userID == other }!
        await sut.remove(target)
        let removed = await rooms.removedMembers
        #expect(removed.count == 1)
        #expect(removed.first?.roomID == room.id)
        #expect(removed.first?.userID == other)
        #expect(sut.members.map(\.userID) == [me])
    }

    @Test func memberCannotRemove() async {
        let (sut, rooms, _) = await makeSUT(myRole: .member)
        let target = sut.members.first { $0.userID == other }!
        await sut.remove(target)
        #expect(await rooms.removedMembers.isEmpty)
        #expect(sut.members.count == 2)
    }

    @Test func toggleMuteCallsRepositoryWithInvertedValue() async {
        let (sut, rooms, room) = await makeSUT(myRole: .member, muted: false)
        await sut.toggleMute()
        let calls = await rooms.mutedCalls
        #expect(calls.count == 1)
        #expect(calls.first?.roomID == room.id)
        #expect(calls.first?.userID == me)
        #expect(calls.first?.muted == true)
        #expect(sut.isMuted == true)
    }

    @Test func leaveReturnsTrueAndCallsRepository() async {
        let (sut, rooms, room) = await makeSUT(myRole: .member)
        #expect(await sut.leave() == true)
        #expect(await rooms.leftRoomIDs == [room.id])
    }

    @Test func removeDeniedByServerShowsPermissionMessage() async {
        let (sut, rooms, _) = await makeSUT(myRole: .owner)
        let target = sut.members.first { $0.userID == other }!
        await rooms.fail(with: RoomError.notPermitted)
        await sut.remove(target)
        #expect(sut.errorMessage == RoomError.notPermitted.userMessage)
        #expect(sut.members.count == 2)
    }

    @Test func successfulRemoveClearsAPreviousError() async {
        let (sut, rooms, _) = await makeSUT(myRole: .owner)
        let target = sut.members.first { $0.userID == other }!
        await rooms.fail(with: RoomError.notPermitted)
        await sut.remove(target)
        #expect(sut.errorMessage != nil)

        await rooms.fail(with: nil)
        await sut.remove(target)
        #expect(sut.errorMessage == nil)
        #expect(sut.members.map(\.userID) == [me])
    }

    @Test func leaveFailureShowsErrorAndReturnsFalse() async {
        let (sut, rooms, _) = await makeSUT(myRole: .member)
        await rooms.fail(with: FakeError())
        #expect(await sut.leave() == false)
        #expect(sut.errorMessage == "操作失敗，請檢查網路後再試一次。")
    }
}
