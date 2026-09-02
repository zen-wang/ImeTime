import Foundation
import Testing
import UIKit
@testable import ImeTime

@MainActor
@Suite struct CreateProfileViewModelTests {
    let uid = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private func makeSUT(profiles: FakeProfileRepository, encoded: Data? = Data([1, 2, 3])) -> CreateProfileViewModel {
        CreateProfileViewModel(userID: uid, profiles: profiles, encodeAvatar: { _ in encoded })
    }

    @Test func emptyNameShowsErrorWithoutCallingRepository() async {
        let profiles = FakeProfileRepository()
        let sut = makeSUT(profiles: profiles)
        sut.displayNameInput = "   "
        let result = await sut.save()
        #expect(result == nil)
        #expect(sut.errorMessage == "請輸入名稱。")
        #expect(await profiles.createCalls.isEmpty)
    }

    @Test func tooLongNameShowsLimitMessage() async {
        let sut = makeSUT(profiles: FakeProfileRepository())
        sut.displayNameInput = String(repeating: "字", count: 21)
        _ = await sut.save()
        #expect(sut.errorMessage == "名稱最多 20 個字。")
    }

    @Test func validNameWithoutAvatarCreatesProfileWithTrimmedName() async {
        let profiles = FakeProfileRepository()
        let sut = makeSUT(profiles: profiles)
        sut.displayNameInput = "  小明 "
        let result = await sut.save()
        #expect(result?.displayName == "小明")
        #expect(await profiles.createCalls == [.init(userID: uid, displayName: "小明", avatarPath: nil)])
        #expect(await profiles.uploadCalls.isEmpty)
    }

    @Test func avatarIsUploadedBeforeCreate() async {
        let profiles = FakeProfileRepository()
        let sut = makeSUT(profiles: profiles)
        sut.displayNameInput = "小明"
        sut.avatarImage = UIImage()
        let result = await sut.save()
        #expect(result?.avatarPath == "11111111-1111-1111-1111-111111111111/avatar.jpg")
        #expect(await profiles.uploadCalls.count == 1)
    }

    @Test func avatarEncodingFailureShowsError() async {
        let profiles = FakeProfileRepository()
        let sut = makeSUT(profiles: profiles, encoded: nil)
        sut.displayNameInput = "小明"
        sut.avatarImage = UIImage()
        let result = await sut.save()
        #expect(result == nil)
        #expect(sut.errorMessage == "頭像處理失敗，請換一張圖片。")
        #expect(await profiles.createCalls.isEmpty)
    }

    @Test func repositoryFailureShowsNetworkError() async {
        let profiles = FakeProfileRepository()
        await profiles.fail(with: FakeError())
        let sut = makeSUT(profiles: profiles)
        sut.displayNameInput = "小明"
        let result = await sut.save()
        #expect(result == nil)
        #expect(sut.errorMessage == "儲存失敗，請檢查網路後再試一次。")
        #expect(sut.isSaving == false)
    }
}
