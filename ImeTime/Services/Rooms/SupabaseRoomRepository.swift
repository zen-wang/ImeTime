import Foundation
import ImeTimeCore
import Supabase

struct SupabaseRoomRepository: RoomRepository {
    let client: SupabaseClient

    func myRooms() async throws -> [RoomSummary] {
        struct Row: Decodable {
            let id: UUID
            let name: String
            let invite_code: String
            let timezone: String
            let max_members: Int
            let created_by: UUID?
            let created_at: Date
            let room_members: [CountRow]
            struct CountRow: Decodable { let count: Int }
        }
        let rows: [Row] = try await mapErrors {
            try await client
                .from("rooms")
                .select("id, name, invite_code, timezone, max_members, created_by, created_at, room_members(count)")
                .is("abandoned_at", value: nil)
                .order("created_at")
                .execute()
                .value
        }
        return rows.map { row in
            RoomSummary(
                room: Room(id: row.id, name: row.name, inviteCode: row.invite_code, timezone: row.timezone,
                           maxMembers: row.max_members, createdBy: row.created_by, createdAt: row.created_at),
                memberCount: row.room_members.first?.count ?? 0
            )
        }
    }

    func createRoom(name: RoomName, timeZoneID: String) async throws -> Room {
        try await mapErrors {
            try await client
                .rpc("create_room", params: ["p_name": name.value, "p_timezone": timeZoneID])
                .single()
                .execute()
                .value
        }
    }

    func joinRoom(code: InviteCode) async throws -> Room {
        struct Response: Decodable {
            let error: String?
            let room: Room?
        }
        let response: Response = try await mapErrors {
            try await client
                .rpc("join_room", params: ["p_code": code.value])
                .execute()
                .value
        }
        if let error = response.error { throw RoomError(serverMessage: error) }
        guard let room = response.room else { throw RoomError.unknown("join_room returned neither room nor error") }
        return room
    }

    func leaveRoom(id: UUID) async throws {
        try await mapErrors {
            _ = try await client
                .rpc("leave_room", params: ["p_room_id": id.uuidString])
                .execute()
        }
    }

    func members(roomID: UUID) async throws -> [RoomMember] {
        try await mapErrors {
            try await client
                .from("room_members")
                .select("room_id, user_id, role, notifications_muted, joined_at, profile:profiles(id, display_name, avatar_path, created_at)")
                .eq("room_id", value: roomID.uuidString)
                .order("joined_at")
                .execute()
                .value
        }
    }

    func removeMember(roomID: UUID, userID: UUID) async throws {
        struct AffectedRow: Decodable { let user_id: UUID }
        // RLS 過濾掉的列不會報錯，只會影響 0 列；不看回傳就會把「沒權限」當成成功
        let removed: [AffectedRow] = try await mapErrors {
            try await client
                .from("room_members")
                .delete(returning: .representation)
                .eq("room_id", value: roomID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value
        }
        guard !removed.isEmpty else { throw RoomError.notPermitted }
    }

    func setMuted(roomID: UUID, userID: UUID, muted: Bool) async throws {
        struct AffectedRow: Decodable { let user_id: UUID }
        let updated: [AffectedRow] = try await mapErrors {
            try await client
                .from("room_members")
                .update(["notifications_muted": muted], returning: .representation)
                .eq("room_id", value: roomID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value
        }
        guard !updated.isEmpty else { throw RoomError.notPermitted }
    }

    /// PostgREST 的錯誤訊息就是 SQL 裡 raise 的字串；其他錯誤原樣丟出。
    private func mapErrors<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as PostgrestError {
            throw RoomError(serverMessage: error.message)
        }
    }
}
