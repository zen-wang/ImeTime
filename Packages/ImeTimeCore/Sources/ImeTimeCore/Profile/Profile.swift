import Foundation

/// 對應 public.profiles 一列。
public struct Profile: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let avatarPath: String?
    public let createdAt: Date

    public init(id: UUID, displayName: String, avatarPath: String?, createdAt: Date) {
        self.id = id
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case createdAt = "created_at"
    }
}
