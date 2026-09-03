import Foundation
import ImeTimeCore
import Observation

@MainActor
@Observable
final class RoomSettingsViewModel {
    let room: Room
    private(set) var members: [RoomMember] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let currentUserID: UUID
    private let rooms: any RoomRepository
    private static let genericError = "操作失敗，請檢查網路後再試一次。"

    init(room: Room, currentUserID: UUID, rooms: any RoomRepository) {
        self.room = room
        self.currentUserID = currentUserID
        self.rooms = rooms
    }

    private var me: RoomMember? { members.first { $0.userID == currentUserID } }
    var isOwner: Bool { me?.role == .owner }
    var isMuted: Bool { me?.notificationsMuted ?? false }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            members = try await rooms.members(roomID: room.id)
        } catch {
            errorMessage = "無法載入成員。"
        }
    }

    func remove(_ member: RoomMember) async {
        guard isOwner, member.userID != currentUserID else { return }
        do {
            try await rooms.removeMember(roomID: room.id, userID: member.userID)
            members = members.filter { $0.userID != member.userID }
        } catch {
            errorMessage = Self.genericError
        }
    }

    func toggleMute() async {
        let newValue = !isMuted
        do {
            try await rooms.setMuted(roomID: room.id, userID: currentUserID, muted: newValue)
            members = members.map { member in
                guard member.userID == currentUserID else { return member }
                return RoomMember(roomID: member.roomID, userID: member.userID, role: member.role,
                                  notificationsMuted: newValue, joinedAt: member.joinedAt, profile: member.profile)
            }
        } catch {
            errorMessage = Self.genericError
        }
    }

    /// 成功回 true，呼叫端應離開此房間的所有畫面。
    func leave() async -> Bool {
        do {
            try await rooms.leaveRoom(id: room.id)
            return true
        } catch {
            errorMessage = Self.genericError
            return false
        }
    }
}
