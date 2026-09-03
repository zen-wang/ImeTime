import Foundation

/// 對應 public.room_members 一列，加上 PostgREST 內嵌的 profiles。
public struct RoomMember: Codable, Hashable, Sendable, Identifiable {
    public enum Role: String, Codable, Hashable, Sendable {
        case owner, member
    }

    public let roomID: UUID
    public let userID: UUID
    public let role: Role
    public let notificationsMuted: Bool
    public let joinedAt: Date
    public let profile: Profile

    public init(roomID: UUID, userID: UUID, role: Role, notificationsMuted: Bool, joinedAt: Date, profile: Profile) {
        self.roomID = roomID
        self.userID = userID
        self.role = role
        self.notificationsMuted = notificationsMuted
        self.joinedAt = joinedAt
        self.profile = profile
    }

    public var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case role, profile
        case roomID = "room_id"
        case userID = "user_id"
        case notificationsMuted = "notifications_muted"
        case joinedAt = "joined_at"
    }
}
