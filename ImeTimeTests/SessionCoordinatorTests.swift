import Foundation
import ImeTimeCore
import Testing
@testable import ImeTime

@MainActor
@Suite struct SessionCoordinatorTests {
    let uid = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    /// 固定時間戳：Profile 的 Equatable 含 createdAt，兩次 Date() 永遠不相等。
    private func makeProfile() -> Profile {
        Profile(id: uid, displayName: "小明", avatarPath: nil, createdAt: Date(timeIntervalSince1970: 1_756_800_000))
    }

    @Test func startsLoading() {
        let sut = SessionCoordinator(auth: FakeAuthService(), profiles: FakeProfileRepository())
        #expect(sut.screen == .loading)
    }

    @Test func signedOutShowsWelcome() async {
        let sut = SessionCoordinator(auth: FakeAuthService(), profiles: FakeProfileRepository())
        await sut.apply(.signedOut)
        #expect(sut.screen == .welcome)
    }

    @Test func signedInWithoutProfileShowsCreateProfile() async {
        let sut = SessionCoordinator(auth: FakeAuthService(), profiles: FakeProfileRepository())
        await sut.apply(.signedIn(userID: uid))
        #expect(sut.screen == .createProfile(userID: uid))
    }

    @Test func signedInWithProfileShowsHome() async {
        let profiles = FakeProfileRepository()
        await profiles.seed(makeProfile())
        let sut = SessionCoordinator(auth: FakeAuthService(), profiles: profiles)
        await sut.apply(.signedIn(userID: uid))
        #expect(sut.screen == .home(makeProfile()))
    }

    @Test func profileFetchFailureShowsFailedAndRetryRecovers() async {
        let profiles = FakeProfileRepository()
        await profiles.fail(with: FakeError())
        let sut = SessionCoordinator(auth: FakeAuthService(), profiles: profiles)
        await sut.apply(.signedIn(userID: uid))
        guard case .failed = sut.screen else {
            Issue.record("expected .failed, got \(sut.screen)")
            return
        }
        await profiles.seed(makeProfile())
        await profiles.fail(with: nil)
        await sut.retry()
        #expect(sut.screen == .home(makeProfile()))
    }

    @Test func profileCreatedMovesToHome() async {
        let sut = SessionCoordinator(auth: FakeAuthService(), profiles: FakeProfileRepository())
        await sut.apply(.signedIn(userID: uid))
        sut.profileCreated(makeProfile())
        #expect(sut.screen == .home(makeProfile()))
    }

    @Test func startConsumesAuthStream() async throws {
        let auth = FakeAuthService()
        let sut = SessionCoordinator(auth: auth, profiles: FakeProfileRepository())
        sut.start()
        auth.emit(.signedOut)
        try await waitUntil { sut.screen == .welcome }
        auth.emit(.signedIn(userID: uid))
        try await waitUntil { sut.screen == .createProfile(userID: uid) }
    }

    /// 最多等 2 秒，每 10ms 檢查一次
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("condition not met within 2s")
    }
}
