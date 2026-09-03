import Foundation

/// 房間列表用：房間 + 目前成員數。
public struct RoomSummary: Hashable, Sendable, Identifiable {
    public let room: Room
    public let memberCount: Int

    public init(room: Room, memberCount: Int) {
        self.room = room
        self.memberCount = memberCount
    }

    public var id: UUID { room.id }
}
