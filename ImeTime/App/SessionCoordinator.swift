import Foundation
import ImeTimeCore
import Observation

/// 根狀態機：登入狀態 × 是否已建立個人檔案 → 目前該顯示哪個畫面。
@MainActor
@Observable
final class SessionCoordinator {
    enum Screen: Equatable {
        case loading
        case welcome
        case createProfile(userID: UUID)
        case home(Profile)
        case failed(message: String)
    }

    private(set) var screen: Screen = .loading

    private let auth: any AuthService
    private let profiles: any ProfileRepository
    private var lastState: AuthState?
    private var observation: Task<Void, Never>?

    init(auth: any AuthService, profiles: any ProfileRepository) {
        self.auth = auth
        self.profiles = profiles
    }

    /// 開始觀察登入狀態。每次迭代才短暫強引用 self，避免 Task 與 coordinator 互相持有。
    func start() {
        observation?.cancel()
        observation = Task { [weak self] in
            guard let states = self?.auth.states() else { return }
            for await state in states {
                guard let self else { return }
                await self.apply(state)
            }
        }
    }

    func apply(_ state: AuthState) async {
        lastState = state
        switch state {
        case .signedOut:
            screen = .welcome
        case .signedIn(let userID):
            await resolveProfile(for: userID)
        }
    }

    func retry() async {
        guard let lastState else { return }
        await apply(lastState)
    }

    func profileCreated(_ profile: Profile) {
        screen = .home(profile)
    }

    private func resolveProfile(for userID: UUID) async {
        do {
            if let profile = try await profiles.fetchProfile(userID: userID) {
                screen = .home(profile)
            } else {
                screen = .createProfile(userID: userID)
            }
        } catch {
            screen = .failed(message: "無法載入你的個人檔案，請檢查網路後重試。")
        }
    }
}
