import Foundation
import Testing
@testable import ImeTimeCore

@Suite struct ProfileDecodingTests {
    @Test func decodesSnakeCaseRow() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","display_name":"小明","avatar_path":null,"created_at":"2026-09-02T10:00:00+00:00"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profile = try decoder.decode(Profile.self, from: Data(json.utf8))
        #expect(profile.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(profile.displayName == "小明")
        #expect(profile.avatarPath == nil)
    }

    @Test func encodesSnakeCaseKeys() throws {
        let profile = Profile(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "小明", avatarPath: "abc/avatar.jpg", createdAt: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder().encode(profile)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["display_name"] as? String == "小明")
        #expect(object["avatar_path"] as? String == "abc/avatar.jpg")
    }
}
