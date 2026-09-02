import Foundation
@testable import ImeTime

actor FakeAuthService: AuthService {
    private let stream: AsyncStream<AuthState>
    private let continuation: AsyncStream<AuthState>.Continuation
    private(set) var signInTokens: [String] = []
    private(set) var signInNonces: [String] = []
    private(set) var signOutCount = 0

    init() {
        (stream, continuation) = AsyncStream<AuthState>.makeStream()
    }

    nonisolated func states() -> AsyncStream<AuthState> { stream }

    nonisolated func emit(_ state: AuthState) {
        continuation.yield(state)
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {
        signInTokens.append(identityToken)
        signInNonces.append(nonce)
        emit(.signedIn(userID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!))
    }

    func signOut() async throws {
        signOutCount += 1
        emit(.signedOut)
    }
}
