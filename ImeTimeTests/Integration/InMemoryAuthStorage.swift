import Foundation
import Supabase

/// 每個測試用戶端各自一份 session 儲存。預設的 Keychain 儲存是全 App 共用的，
/// 兩個 SupabaseClient 會互相踩掉登入狀態，兩個使用者的測試就寫不出來。
final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        items[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return items[key]
    }

    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        items[key] = nil
    }
}
