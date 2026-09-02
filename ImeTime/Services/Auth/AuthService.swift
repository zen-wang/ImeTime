import Foundation

enum AuthState: Equatable, Sendable {
    case signedOut
    case signedIn(userID: UUID)
}

/// 登入狀態來源。`states()` 先送出目前狀態，之後每次變化都送；App 存活期間不會結束。
protocol AuthService: Sendable {
    func states() -> AsyncStream<AuthState>
    /// `nonce` 是產生請求時的原始亂數；Apple 的 request.nonce 必須是它的 SHA-256 hex。
    func signInWithApple(identityToken: String, nonce: String) async throws
    func signOut() async throws
}
