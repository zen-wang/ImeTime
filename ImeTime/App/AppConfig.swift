import Foundation

/// 讀取設定時可能出現的錯誤。App 啟動階段用它換掉 fatalError，讓設定問題看得見而不是直接閃退。
enum AppConfigError: Error, Equatable, Sendable {
    /// xcconfig 注入的 SupabaseURL 空白、無法解析、scheme 不是 http/https，或沒有 host。附帶原始字串方便排查。
    case invalidSupabaseURL(String)
    /// xcconfig 注入的 SupabaseAnonKey 是空的。
    case missingAnonKey
}

extension AppConfigError {
    /// 給使用者看的繁體中文說明，直接指出要填哪個 key、填在哪個檔案。
    var userMessage: String {
        switch self {
        case .invalidSupabaseURL(let rawValue):
            let shown = rawValue.isEmpty ? "（空白）" : rawValue
            return """
            Supabase 網址無效：\(shown)
            Debug 建置請確認 Config/Local.xcconfig 的 LOCAL_SUPABASE_ANON_KEY 已填，且本機 Supabase 已啟動；\
            Release 建置請確認 Config/Local.xcconfig 的 PROD_SUPABASE_URL 與 PROD_SUPABASE_ANON_KEY 已填。
            """
        case .missingAnonKey:
            return """
            缺少 Supabase anon key。
            Debug 建置請在 Config/Local.xcconfig 填入 LOCAL_SUPABASE_ANON_KEY（執行 supabase status -o env 可取得，或直接跑 make bootstrap）；\
            Release 建置請填入 Config/Local.xcconfig 的 PROD_SUPABASE_URL 與 PROD_SUPABASE_ANON_KEY。
            """
        }
    }
}

/// 從 Info.plist 讀取由 xcconfig 注入的環境值。缺值時丟出 AppConfigError，由 App 顯示設定錯誤畫面。
struct AppConfig: Sendable {
    let supabaseURL: URL
    let supabaseAnonKey: String

    static func load(bundle: Bundle = .main) throws(AppConfigError) -> AppConfig {
        let urlString = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? ""
        let key = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""

        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty
        else {
            throw .invalidSupabaseURL(urlString)
        }
        guard !key.isEmpty else { throw .missingAnonKey }

        return AppConfig(supabaseURL: url, supabaseAnonKey: key)
    }
}
