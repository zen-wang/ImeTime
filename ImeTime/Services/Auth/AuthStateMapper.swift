import Foundation
import Supabase

/// 把 supabase-swift 的 auth 事件轉成 App 自己的狀態。純函式，方便測試。
/// 回傳 nil 表示這個事件不影響登入狀態。
enum AuthStateMapper {
    static func map(event: AuthChangeEvent, userID: UUID?) -> AuthState? {
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
            guard let userID else {
                return event == .initialSession ? .signedOut : nil
            }
            return .signedIn(userID: userID)
        case .signedOut, .userDeleted:
            return .signedOut
        default:
            return nil
        }
    }
}
