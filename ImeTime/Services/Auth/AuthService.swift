import Foundation

enum AuthState: Equatable, Sendable {
    case signedOut
    case signedIn(userID: UUID)
}

/// 登入狀態來源。`states()` 先送出目前狀態，之後每次變化都送；App 存活期間不會結束。
protocol AuthService: Sendable {
    func states() -> AsyncStream<AuthState>
    func signInWithApple(identityToken: String) async throws
    func signOut() async throws
}
