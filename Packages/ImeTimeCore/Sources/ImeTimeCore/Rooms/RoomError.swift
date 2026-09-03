/// 房間 RPC 的錯誤。serverMessage 與 SQL 的 raise/jsonb error 字串一一對應。
public enum RoomError: Error, Equatable, Sendable {
    case invalidCode
    case roomFull
    case alreadyMember
    case rateLimited
    case notMember
    case invalidName
    case invalidTimezone
    case profileRequired
    case notAuthenticated
    case unknown(String)

    public init(serverMessage: String) {
        switch serverMessage {
        case "invalid_code": self = .invalidCode
        case "room_full": self = .roomFull
        case "already_member": self = .alreadyMember
        case "rate_limited": self = .rateLimited
        case "not_member": self = .notMember
        case "invalid_name": self = .invalidName
        case "invalid_timezone": self = .invalidTimezone
        case "profile_required": self = .profileRequired
        case "not_authenticated": self = .notAuthenticated
        default: self = .unknown(serverMessage)
        }
    }

    public var userMessage: String {
        switch self {
        case .invalidCode: "找不到這個邀請碼，請確認後再試。"
        case .roomFull: "這個房間已經滿了。"
        case .alreadyMember: "你已經在這個房間裡了。"
        case .rateLimited: "嘗試太多次了，請一分鐘後再試。"
        case .notMember: "你不在這個房間裡。"
        case .invalidName: "房間名稱需為 1 到 30 個字。"
        case .invalidTimezone: "無法辨識你的時區設定。"
        case .profileRequired: "請先建立個人檔案。"
        case .notAuthenticated: "請先登入。"
        case .unknown: "發生未知錯誤，請稍後再試。"
        }
    }
}
