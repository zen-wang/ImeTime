import ImeTimeCore
import SwiftUI

struct RoomsListView: View {
    let viewModel: RoomsListViewModel
    @Binding var path: [HomeRoute]

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
            case .empty:
                ContentUnavailableView {
                    Label("還沒有房間", systemImage: "person.2")
                } description: {
                    Text("建立一個房間邀請朋友，或輸入朋友給你的邀請碼。")
                } actions: {
                    actionButtons
                }
            case .loaded(let summaries):
                List {
                    ForEach(summaries) { summary in
                        Button { path.append(.room(summary.room)) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(summary.room.name).font(.headline)
                                    Text("\(summary.memberCount) 位成員").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                    }
                    Section { actionButtons }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("載入失敗", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("重試") { Task { await viewModel.load() } }
                }
            }
        }
        .task { await viewModel.load() }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button("建立房間") { path.append(.createRoom) }
                .buttonStyle(.borderedProminent)
            Button("用邀請碼加入") { path.append(.joinRoom) }
                .buttonStyle(.bordered)
        }
    }
}
