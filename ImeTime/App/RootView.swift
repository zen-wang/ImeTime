import SwiftUI

struct RootView: View {
    let coordinator: SessionCoordinator
    let environment: AppEnvironment

    var body: some View {
        switch coordinator.screen {
        case .loading:
            ProgressView()
        case .welcome:
            WelcomeView(auth: environment.auth)
        case .createProfile(let userID):
            CreateProfileView(userID: userID, profiles: environment.profiles, onCreated: coordinator.profileCreated)
                .id(userID)
        case .home(let profile):
            HomeView(
                profile: profile,
                environment: environment,
                onSignOut: { Task { try? await environment.auth.signOut() } }
            )
        case .failed(let message):
            ContentUnavailableView {
                Label("載入失敗", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重試") { Task { await coordinator.retry() } }
            }
        }
    }
}
