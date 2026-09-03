import Foundation
import ImeTimeCore

protocol RoomRepository: Sendable {
    /// 我所屬、未被放棄的房間，依建立時間排序。
    func myRooms() async throws -> [RoomSummary]
    func createRoom(name: RoomName, timeZoneID: String) async throws -> Room
    /// 失敗時丟 RoomError（invalidCode / roomFull / alreadyMember / rateLimited …）。
    func joinRoom(code: InviteCode) async throws -> Room
    func leaveRoom(id: UUID) async throws
    func members(roomID: UUID) async throws -> [RoomMember]
    func removeMember(roomID: UUID, userID: UUID) async throws
    func setMuted(roomID: UUID, userID: UUID, muted: Bool) async throws
}
