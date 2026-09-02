import Foundation
import ImeTimeCore

protocol ProfileRepository: Sendable {
    /// 找不到回 nil（首次登入尚未建立檔案）。
    func fetchProfile(userID: UUID) async throws -> Profile?
    func createProfile(userID: UUID, displayName: DisplayName, avatarPath: String?) async throws -> Profile
    /// 上傳（覆寫）頭像，回傳 storage 路徑 `{uid}/avatar.jpg`。
    func uploadAvatar(userID: UUID, jpegData: Data) async throws -> String
    func avatarURL(path: String) -> URL?
}
