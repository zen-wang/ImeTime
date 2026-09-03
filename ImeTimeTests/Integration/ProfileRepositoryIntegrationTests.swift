import Foundation
import ImeTimeCore
import Testing
import UIKit
@testable import ImeTime

@Suite(.enabled(if: LocalSupabase.isEnabled), .serialized)
struct ProfileRepositoryIntegrationTests {
    @Test func returnsNilBeforeCreateThenRoundTripsTheRow() async throws {
        let (client, userID) = try await LocalSupabase.signUpUser()
        let repository = SupabaseProfileRepository(client: client)

        let before = try await repository.fetchProfile(userID: userID)
        #expect(before == nil)

        let name = try DisplayName("小明")
        let created = try await repository.createProfile(userID: userID, displayName: name, avatarPath: nil)
        #expect(created.id == userID)
        #expect(created.displayName == "小明")
        #expect(created.avatarPath == nil)

        // 相等即證明 created_at 的微秒時間戳在 insert 與 select 兩條路徑上解碼一致
        let fetched = try #require(await repository.fetchProfile(userID: userID))
        #expect(fetched == created)
    }

    @Test func uploadsAvatarToLowercasedFolderAndServesTheSameBytes() async throws {
        let (client, userID) = try await LocalSupabase.signUpUser()
        let repository = SupabaseProfileRepository(client: client)
        let name = try DisplayName("頭像")
        _ = try await repository.createProfile(userID: userID, displayName: name, avatarPath: nil)

        let jpeg = try #require(AvatarImageEncoder.jpegData(from: Self.solidImage()))
        let path = try await repository.uploadAvatar(userID: userID, jpegData: jpeg)
        // Storage 政策比對 auth.uid()::text（小寫）；大寫路徑會被 42501 擋下
        #expect(path == "\(userID.uuidString.lowercased())/avatar.jpg")

        let url = try #require(repository.avatarURL(path: path))
        let (data, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == jpeg)
    }

    private static func solidImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }
}
