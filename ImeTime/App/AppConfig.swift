import Foundation

/// 從 Info.plist 讀取由 xcconfig 注入的環境值。缺值時立刻 fatalError，避免帶著錯設定跑很久才失敗。
struct AppConfig: Sendable {
    let supabaseURL: URL
    let supabaseAnonKey: String

    static func load(bundle: Bundle = .main) -> AppConfig {
        let urlString = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? ""
        let key = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
        guard let url = URL(string: urlString), url.host() != nil, !key.isEmpty else {
            fatalError("""
            缺少 SupabaseURL / SupabaseAnonKey。
            請複製 Config/Local.xcconfig.example 為 Config/Local.xcconfig，填入 LOCAL_SUPABASE_ANON_KEY 後重新建置。
            目前讀到 SupabaseURL="\(urlString)" SupabaseAnonKey.isEmpty=\(key.isEmpty)
            """)
        }
        return AppConfig(supabaseURL: url, supabaseAnonKey: key)
    }
}
