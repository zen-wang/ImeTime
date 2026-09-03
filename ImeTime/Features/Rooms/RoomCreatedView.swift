import ImeTimeCore
import SwiftUI

struct RoomCreatedView: View {
    let room: Room
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("「\(room.name)」建立好了")
                .font(.title2.bold())
            Text("把邀請碼傳給朋友")
                .foregroundStyle(.secondary)
            Text(room.inviteCode)
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .kerning(6)
                .padding(.vertical, 8)
            ShareLink(item: InviteShare.text(for: room)) {
                Label("分享邀請", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
            Button("進入房間", action: onDone)
        }
        .padding(24)
        .navigationBarBackButtonHidden()
    }
}
