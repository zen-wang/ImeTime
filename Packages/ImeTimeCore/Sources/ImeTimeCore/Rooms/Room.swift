import Foundation

/// 對應 public.rooms 一列。abandoned_at 不解碼：App 只會看到未 abandoned 的房間。
public struct Room: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let inviteCode: String
    public let timezone: String
    public let maxMembers: Int
    /// 建立者的帳號刪除後會變成 nil；擁有權看 room_members.role，不看這裡。
    public let createdBy: UUID?
    public let createdAt: Date

    public init(id: UUID, name: String, inviteCode: String, timezone: String, maxMembers: Int, createdBy: UUID?, createdAt: Date) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.timezone = timezone
        self.maxMembers = maxMembers
        self.createdBy = createdBy
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, timezone
        case inviteCode = "invite_code"
        case maxMembers = "max_members"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}
