import ImeTimeCore
import SwiftUI

struct CreateRoomView: View {
    @State private var viewModel: CreateRoomViewModel
    let onCreated: (Room) -> Void

    init(rooms: any RoomRepository, onCreated: @escaping (Room) -> Void) {
        _viewModel = State(initialValue: CreateRoomViewModel(rooms: rooms))
        self.onCreated = onCreated
    }

    var body: some View {
        Form {
            Section("房間名稱") {
                TextField("例如：週末小隊（最多 \(RoomName.maxLength) 字）", text: $viewModel.nameInput)
            }
            Section {
                Text("房間的一天從凌晨 4 點開始，時區採用你目前的裝置設定（\(TimeZone.current.identifier)）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            Button {
                Task { if let room = await viewModel.create() { onCreated(room) } }
            } label: {
                if viewModel.isSaving {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("建立").frame(maxWidth: .infinity)
                }
            }
            .disabled(viewModel.isSaving)
        }
        .navigationTitle("建立房間")
    }
}
