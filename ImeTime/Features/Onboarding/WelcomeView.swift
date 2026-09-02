import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    let auth: any AuthService
    @State private var errorMessage: String?
    @State private var currentNonce: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("ImeTime")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("每小時 2 秒，和朋友一起記錄真實生活。")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            SignInWithAppleButton(.signIn) { request in
                let nonce = AppleNonce.random()
                currentNonce = nonce
                request.requestedScopes = []
                request.nonce = AppleNonce.sha256Hex(nonce)
            } onCompletion: { result in
                Task { await handle(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            Link("隱私權政策", destination: AppLinks.privacyPolicy)
                .font(.footnote)
        }
        .padding(24)
        .alert("登入失敗", isPresented: isShowingError) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func handle(_ result: Result<ASAuthorization, any Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "無法完成 Apple 登入，請再試一次。"
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce
            else {
                errorMessage = "Apple 沒有回傳有效的登入資訊。"
                return
            }
            do {
                try await auth.signInWithApple(identityToken: token, nonce: nonce)
            } catch {
                errorMessage = "登入伺服器失敗，請確認網路與 Supabase 是否啟動。"
            }
        }
    }
}
