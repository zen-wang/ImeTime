import Foundation
import ImeTimeCore
@testable import ImeTime

actor FakeProfileRepository: ProfileRepository {
    struct CreateCall: Equatable { let userID: UUID; let displayName: String; let avatarPath: String? }

    var profiles: [UUID: Profile] = [:]
    var errorToThrow: Error?
    private(set) var createCalls: [CreateCall] = []
    private(set) var uploadCalls: [(userID: UUID, bytes: Int)] = []

    func seed(_ profile: Profile) { profiles[profile.id] = profile }
    func fail(with error: Error?) { errorToThrow = error }

    func fetchProfile(userID: UUID) async throws -> Profile? {
        if let errorToThrow { throw errorToThrow }
        return profiles[userID]
    }

    func createProfile(userID: UUID, displayName: DisplayName, avatarPath: String?) async throws -> Profile {
        if let errorToThrow { throw errorToThrow }
        createCalls.append(CreateCall(userID: userID, displayName: displayName.value, avatarPath: avatarPath))
        let profile = Profile(id: userID, displayName: displayName.value, avatarPath: avatarPath, createdAt: Date())
        profiles[userID] = profile
        return profile
    }

    func uploadAvatar(userID: UUID, jpegData: Data) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        uploadCalls.append((userID: userID, bytes: jpegData.count))
        return "\(userID.uuidString.lowercased())/avatar.jpg"
    }

    nonisolated func avatarURL(path: String) -> URL? {
        URL(string: "https://example.test/avatars/\(path)")
    }
}

struct FakeError: Error, Equatable {}
