import ImeTimeCore
import SwiftUI

/// P1 佔位：P2 會換成當日時間線。
struct RoomView: View {
    let room: Room
    let currentUserID: UUID
    let environment: AppEnvironment
    @Binding var path: [HomeRoute]

    var body: some View {
        ContentUnavailableView {
            Label(room.name, systemImage: "video")
        } description: {
            Text("時間線將在下一階段加入。先用右上角邀請朋友吧。")
        }
        .navigationTitle(room.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    path.append(.roomSettings(room))
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
    }
}
