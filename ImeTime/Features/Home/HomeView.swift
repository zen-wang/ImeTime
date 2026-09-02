import ImeTimeCore
import SwiftUI

/// P0 佔位：顯示個人檔案與登出。P1 會改成房間列表。
struct HomeView: View {
    let profile: Profile
    let avatarURL: URL?
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                Text("嗨，\(profile.displayName)")
                    .font(.title2.bold())
                Text("房間功能將在下一階段加入。")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("ImeTime")
            .toolbar {
                Button("登出", role: .destructive, action: onSignOut)
            }
        }
    }
}
