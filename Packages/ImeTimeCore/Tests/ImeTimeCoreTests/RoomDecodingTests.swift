import Foundation
import Testing
@testable import ImeTimeCore

@Suite struct RoomDecodingTests {
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @Test func decodesRoomRow() throws {
        let json = """
        {"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"R1","invite_code":"ABCDEF","timezone":"Asia/Taipei",
         "max_members":12,"created_by":"11111111-1111-1111-1111-111111111111","abandoned_at":null,
         "created_at":"2026-09-02T10:00:00+00:00"}
        """
        let room = try decoder.decode(Room.self, from: Data(json.utf8))
        #expect(room.name == "R1")
        #expect(room.inviteCode == "ABCDEF")
        #expect(room.maxMembers == 12)
    }

    @Test func decodesRoomMemberWithEmbeddedProfile() throws {
        let json = """
        {"room_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","user_id":"11111111-1111-1111-1111-111111111111",
         "role":"owner","notifications_muted":false,"joined_at":"2026-09-02T10:00:00+00:00",
         "profile":{"id":"11111111-1111-1111-1111-111111111111","display_name":"A","avatar_path":null,"created_at":"2026-09-01T00:00:00+00:00"}}
        """
        let member = try decoder.decode(RoomMember.self, from: Data(json.utf8))
        #expect(member.role == .owner)
        #expect(member.profile.displayName == "A")
        #expect(member.id == member.userID)
    }
}
