import ImeTimeCore
import SwiftUI

struct JoinRoomView: View {
    @State private var viewModel: JoinRoomViewModel
    @FocusState private var isFocused: Bool
    let onJoined: (Room) -> Void

    init(rooms: any RoomRepository, onJoined: @escaping (Room) -> Void) {
        _viewModel = State(initialValue: JoinRoomViewModel(rooms: rooms))
        self.onJoined = onJoined
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("輸入朋友給你的 6 碼邀請碼")
                .foregroundStyle(.secondary)
            TextField("ABCD23", text: $viewModel.codeInput)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .focused($isFocused)
                .onChange(of: viewModel.codeInput) { _, newValue in
                    // 只保留字母表內的字元、最多 6 碼、自動大寫
                    let filtered = newValue.uppercased().filter { InviteCode.alphabet.contains($0) }
                    viewModel.codeInput = String(filtered.prefix(InviteCode.length))
                }
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            Button {
                Task { if let room = await viewModel.join() { onJoined(room) } }
            } label: {
                if viewModel.isJoining {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("加入").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSubmit || viewModel.isJoining)
            Spacer()
        }
        .padding(24)
        .navigationTitle("加入房間")
        .onAppear { isFocused = true }
    }
}
