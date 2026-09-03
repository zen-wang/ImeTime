import Foundation
import ImeTimeCore
@testable import ImeTime

actor FakeRoomRepository: RoomRepository {
    var summaries: [RoomSummary] = []
    var membersByRoom: [UUID: [RoomMember]] = [:]
    var errorToThrow: Error?
    /// joinRoom 的結果：nil 表示回傳一個新房間；設定 RoomError 則丟出。
    var joinError: RoomError?

    private(set) var createdRooms: [(name: String, timeZoneID: String)] = []
    private(set) var joinedCodes: [String] = []
    private(set) var leftRoomIDs: [UUID] = []
    private(set) var removedMembers: [(roomID: UUID, userID: UUID)] = []
    private(set) var mutedCalls: [(roomID: UUID, userID: UUID, muted: Bool)] = []

    func set(summaries: [RoomSummary]) { self.summaries = summaries }
    func set(members: [RoomMember], for roomID: UUID) { membersByRoom[roomID] = members }
    func fail(with error: Error?) { errorToThrow = error }
    func failJoin(with error: RoomError?) { joinError = error }

    static func makeRoom(name: String = "R", code: String = "ABCDEF", createdBy: UUID? = UUID()) -> Room {
        Room(id: UUID(), name: name, inviteCode: code, timezone: "Asia/Taipei", maxMembers: 12, createdBy: createdBy, createdAt: Date())
    }

    func myRooms() async throws -> [RoomSummary] {
        if let errorToThrow { throw errorToThrow }
        return summaries
    }

    func createRoom(name: RoomName, timeZoneID: String) async throws -> Room {
        if let errorToThrow { throw errorToThrow }
        createdRooms.append((name: name.value, timeZoneID: timeZoneID))
        return Self.makeRoom(name: name.value)
    }

    func joinRoom(code: InviteCode) async throws -> Room {
        if let errorToThrow { throw errorToThrow }
        joinedCodes.append(code.value)
        if let joinError { throw joinError }
        return Self.makeRoom(code: code.value)
    }

    func leaveRoom(id: UUID) async throws {
        if let errorToThrow { throw errorToThrow }
        leftRoomIDs.append(id)
    }

    func members(roomID: UUID) async throws -> [RoomMember] {
        if let errorToThrow { throw errorToThrow }
        return membersByRoom[roomID] ?? []
    }

    func removeMember(roomID: UUID, userID: UUID) async throws {
        if let errorToThrow { throw errorToThrow }
        removedMembers.append((roomID: roomID, userID: userID))
        membersByRoom[roomID]?.removeAll { $0.userID == userID }
    }

    func setMuted(roomID: UUID, userID: UUID, muted: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        mutedCalls.append((roomID: roomID, userID: userID, muted: muted))
        membersByRoom[roomID] = membersByRoom[roomID]?.map { member in
            guard member.userID == userID else { return member }
            return RoomMember(roomID: member.roomID, userID: member.userID, role: member.role,
                              notificationsMuted: muted, joinedAt: member.joinedAt, profile: member.profile)
        }
    }
}
