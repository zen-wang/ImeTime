import Foundation
import ImeTimeCore
import Supabase

struct SupabaseProfileRepository: ProfileRepository {
    let client: SupabaseClient

    func fetchProfile(userID: UUID) async throws -> Profile? {
        let rows: [Profile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func createProfile(userID: UUID, displayName: DisplayName, avatarPath: String?) async throws -> Profile {
        struct NewProfile: Encodable {
            let id: UUID
            let display_name: String
            let avatar_path: String?
        }
        return try await client
            .from("profiles")
            .insert(NewProfile(id: userID, display_name: displayName.value, avatar_path: avatarPath), returning: .representation)
            .single()
            .execute()
            .value
    }

    func uploadAvatar(userID: UUID, jpegData: Data) async throws -> String {
        // Storage 政策比對 auth.uid()::text（小寫），路徑必須小寫
        let path = "\(userID.uuidString.lowercased())/avatar.jpg"
        try await client.storage
            .from("avatars")
            .upload(path, data: jpegData, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return path
    }

    func avatarURL(path: String) -> URL? {
        try? client.storage.from("avatars").getPublicURL(path: path)
    }
}
