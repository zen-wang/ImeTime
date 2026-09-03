import Foundation
import ImeTimeCore
import Testing
@testable import ImeTime

@Suite(.enabled(if: LocalSupabase.isEnabled), .serialized)
struct RoomRepositoryIntegrationTests {
    @Test func createsRoomAsOwnerAndListsItWithMemberCount() async throws {
        let owner = try await LocalSupabase.signUpUserWithProfile(displayName: "房主")
        let room = try await owner.rooms.createRoom(name: try RoomName("週末小隊"), timeZoneID: "Asia/Taipei")

        #expect(room.name == "週末小隊")
        #expect(room.maxMembers == 12)
        #expect(InviteCode(exact: room.inviteCode) != nil)

        let summaries = try await owner.rooms.myRooms()
        let summary = try #require(summaries.first { $0.room.id == room.id })
        #expect(summary.memberCount == 1)
    }

    @Test func secondUserJoinsWithNormalizedCodeAndShowsUpInMembers() async throws {
        let owner = try await LocalSupabase.signUpUserWithProfile(displayName: "房主")
        let guest = try await LocalSupabase.signUpUserWithProfile(displayName: "客人")
        let room = try await owner.rooms.createRoom(name: try RoomName("週末小隊"), timeZoneID: "Asia/Taipei")

        let code = try #require(InviteCode(userInput: " \(room.inviteCode.lowercased()) "))
        let joined = try await guest.rooms.joinRoom(code: code)
        #expect(joined.id == room.id)

        // memberCount 只驗證 1 的話，常數 1 或 limit(1) 的錯誤實作也會通過
        let summary = try #require(try await owner.rooms.myRooms().first { $0.room.id == room.id })
        #expect(summary.memberCount == 2)

        let members = try await owner.rooms.members(roomID: room.id)
        #expect(members.count == 2)
        #expect(members.first { $0.userID == owner.userID }?.role == .owner)
        let guestMember = try #require(members.first { $0.userID == guest.userID })
        #expect(guestMember.role == .member)
        // profiles 的 select 政策要讓同房間成員互相看得到，內嵌查詢才拿得到名字
        #expect(guestMember.profile.displayName == "客人")
    }

    @Test func joiningTwiceReportsAlreadyMember() async throws {
        let owner = try await LocalSupabase.signUpUserWithProfile(displayName: "房主")
        let guest = try await LocalSupabase.signUpUserWithProfile(displayName: "客人")
        let room = try await owner.rooms.createRoom(name: try RoomName("週末小隊"), timeZoneID: "Asia/Taipei")
        let code = try #require(InviteCode(exact: room.inviteCode))

        _ = try await guest.rooms.joinRoom(code: code)
        await #expect(throws: RoomError.alreadyMember) {
            _ = try await guest.rooms.joinRoom(code: code)
        }
    }

    @Test func unknownCodeReportsInvalidCode() async throws {
        let user = try await LocalSupabase.signUpUserWithProfile(displayName: "路人")
        let code = try #require(InviteCode(exact: "ZZZZZZ"))
        await #expect(throws: RoomError.invalidCode) {
            _ = try await user.rooms.joinRoom(code: code)
        }
    }

    @Test func leavingRemovesTheRoomFromMyRooms() async throws {
        let owner = try await LocalSupabase.signUpUserWithProfile(displayName: "房主")
        let guest = try await LocalSupabase.signUpUserWithProfile(displayName: "客人")
        let room = try await owner.rooms.createRoom(name: try RoomName("週末小隊"), timeZoneID: "Asia/Taipei")
        _ = try await guest.rooms.joinRoom(code: try #require(InviteCode(exact: room.inviteCode)))

        try await guest.rooms.leaveRoom(id: room.id)

        let guestRooms = try await guest.rooms.myRooms()
        #expect(!guestRooms.contains { $0.room.id == room.id })
        let ownerMembers = try await owner.rooms.members(roomID: room.id)
        #expect(ownerMembers.map(\.userID) == [owner.userID])
    }

    @Test func ownerMutesSelfThenRemovesGuest() async throws {
        let owner = try await LocalSupabase.signUpUserWithProfile(displayName: "房主")
        let guest = try await LocalSupabase.signUpUserWithProfile(displayName: "客人")
        let room = try await owner.rooms.createRoom(name: try RoomName("週末小隊"), timeZoneID: "Asia/Taipei")
        _ = try await guest.rooms.joinRoom(code: try #require(InviteCode(exact: room.inviteCode)))

        // 成功的寫入必須回傳受影響的列；若 returning 變成 .minimal，這兩行會變成 notPermitted
        try await owner.rooms.setMuted(roomID: room.id, userID: owner.userID, muted: true)
        let afterMute = try await owner.rooms.members(roomID: room.id)
        #expect(afterMute.first { $0.userID == owner.userID }?.notificationsMuted == true)

        try await owner.rooms.removeMember(roomID: room.id, userID: guest.userID)
        let afterRemove = try await owner.rooms.members(roomID: room.id)
        #expect(afterRemove.map(\.userID) == [owner.userID])
    }
}
