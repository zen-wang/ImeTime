import ImeTimeCore
import SwiftUI

struct RoomSettingsView: View {
    @State private var viewModel: RoomSettingsViewModel
    @State private var isConfirmingLeave = false
    let environment: AppEnvironment
    let onLeft: () -> Void

    init(room: Room, currentUserID: UUID, environment: AppEnvironment, onLeft: @escaping () -> Void) {
        _viewModel = State(initialValue: RoomSettingsViewModel(room: room, currentUserID: currentUserID, rooms: environment.rooms))
        self.environment = environment
        self.onLeft = onLeft
    }

    var body: some View {
        List {
            Section("邀請碼") {
                HStack {
                    Text(viewModel.room.inviteCode)
                        .font(.system(.title2, design: .monospaced).bold())
                        .kerning(4)
                    Spacer()
                    ShareLink(item: InviteShare.text(for: viewModel.room)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }

            Section("成員（\(viewModel.members.count)/\(viewModel.room.maxMembers)）") {
                ForEach(viewModel.members) { member in
                    HStack(spacing: 12) {
                        AsyncImage(url: member.profile.avatarPath.flatMap(environment.profiles.avatarURL)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        Text(member.profile.displayName)
                        if member.role == .owner {
                            Text("管理員").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .swipeActions {
                        if viewModel.isOwner, member.role != .owner {
                            Button("移除", role: .destructive) {
                                Task { await viewModel.remove(member) }
                            }
                        }
                    }
                }
            }

            Section("通知") {
                Toggle("這個房間的通知", isOn: Binding(
                    get: { !viewModel.isMuted },
                    set: { _ in Task { await viewModel.toggleMute() } }
                ))
            }

            Section {
                Button("離開房間", role: .destructive) { isConfirmingLeave = true }
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle(viewModel.room.name)
        .task { await viewModel.load() }
        .confirmationDialog("離開「\(viewModel.room.name)」？", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button("離開房間", role: .destructive) {
                Task { if await viewModel.leave() { onLeft() } }
            }
        } message: {
            Text("你的片段會留在房間裡，但你不再能看到這個房間。")
        }
    }
}
