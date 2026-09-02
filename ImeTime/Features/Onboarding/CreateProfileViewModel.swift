import Foundation
import ImeTimeCore
import Observation
import UIKit

@MainActor
@Observable
final class CreateProfileViewModel {
    var displayNameInput = ""
    var avatarImage: UIImage?
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private let userID: UUID
    private let profiles: any ProfileRepository
    private let encodeAvatar: @Sendable (UIImage) -> Data?

    init(
        userID: UUID,
        profiles: any ProfileRepository,
        encodeAvatar: @escaping @Sendable (UIImage) -> Data? = { AvatarImageEncoder.jpegData(from: $0) }
    ) {
        self.userID = userID
        self.profiles = profiles
        self.encodeAvatar = encodeAvatar
    }

    /// 成功回傳建立的 Profile；失敗回 nil 並設定 errorMessage。
    func save() async -> Profile? {
        errorMessage = nil
        let name: DisplayName
        do {
            name = try DisplayName(displayNameInput)
        } catch {
            errorMessage = error.userMessage
            return nil
        }

        var avatarData: Data?
        if let avatarImage {
            guard let data = encodeAvatar(avatarImage) else {
                errorMessage = "頭像處理失敗，請換一張圖片。"
                return nil
            }
            avatarData = data
        }

        isSaving = true
        defer { isSaving = false }
        do {
            var avatarPath: String?
            if let avatarData {
                avatarPath = try await profiles.uploadAvatar(userID: userID, jpegData: avatarData)
            }
            return try await profiles.createProfile(userID: userID, displayName: name, avatarPath: avatarPath)
        } catch {
            errorMessage = "儲存失敗，請檢查網路後再試一次。"
            return nil
        }
    }
}

extension NameValidationError {
    var userMessage: String {
        switch self {
        case .empty: "請輸入名稱。"
        case .tooLong(let max): "名稱最多 \(max) 個字。"
        }
    }
}
