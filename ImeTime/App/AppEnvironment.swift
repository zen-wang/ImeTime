import Foundation
import Supabase

/// 依賴注入容器。live() 建立真正的 Supabase 實作；測試直接用 Fakes 建構各 view model。
@MainActor
struct AppEnvironment {
    let auth: any AuthService
    let profiles: any ProfileRepository
    let rooms: any RoomRepository

    static func live(config: AppConfig) -> AppEnvironment {
        let client = SupabaseClient(supabaseURL: config.supabaseURL, supabaseKey: config.supabaseAnonKey)
        return AppEnvironment(
            auth: SupabaseAuthService(client: client),
            profiles: SupabaseProfileRepository(client: client),
            rooms: SupabaseRoomRepository(client: client)
        )
    }
}
