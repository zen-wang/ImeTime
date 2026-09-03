import Foundation
import ImeTimeCore
import Supabase
@testable import ImeTime

enum IntegrationSetupError: Error {
    case signUpDidNotReturnSession(email: String)
}

/// 對本機 Supabase stack 的整合測試支援。
/// 只有 `make test-integration` 會設定 IMETIME_INTEGRATION=1；一般 `make test-app` 會整組跳過，維持離線可跑。
enum LocalSupabase {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["IMETIME_INTEGRATION"] == "1"
    }

    /// 每次都建立獨立 session 儲存的 client，讓同一個測試能同時操作兩個使用者。
    static func makeClient() throws -> SupabaseClient {
        let config = try AppConfig.load()
        return SupabaseClient(
            supabaseURL: config.supabaseURL,
            supabaseKey: config.supabaseAnonKey,
            options: SupabaseClientOptions(auth: .init(storage: InMemoryAuthStorage()))
        )
    }

    /// 以隨機 email 註冊新使用者。本機關閉了 email 確認，signUp 會直接回傳 session。
    static func signUpUser() async throws -> (client: SupabaseClient, userID: UUID) {
        let client = try makeClient()
        let email = "itest-\(UUID().uuidString.lowercased())@example.com"
        let response = try await client.auth.signUp(email: email, password: "itest-password-123")
        guard let session = response.session else {
            throw IntegrationSetupError.signUpDidNotReturnSession(email: email)
        }
        return (client, session.user.id)
    }

    /// create_room 與 join_room 都要求 profile 存在，所以一併建立。
    static func signUpUserWithProfile(
        displayName: String
    ) async throws -> (client: SupabaseClient, userID: UUID, profiles: SupabaseProfileRepository, rooms: SupabaseRoomRepository) {
        let (client, userID) = try await signUpUser()
        let profiles = SupabaseProfileRepository(client: client)
        let name = try DisplayName(displayName)
        _ = try await profiles.createProfile(userID: userID, displayName: name, avatarPath: nil)
        return (client, userID, profiles, SupabaseRoomRepository(client: client))
    }
}
