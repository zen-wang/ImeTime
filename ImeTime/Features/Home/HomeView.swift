import ImeTimeCore
import SwiftUI

struct HomeView: View {
    let profile: Profile
    let environment: AppEnvironment
    let onSignOut: () -> Void

    @State private var path: [HomeRoute] = []
    @State private var listViewModel: RoomsListViewModel
    @State private var createdRoom: Room?

    init(profile: Profile, environment: AppEnvironment, onSignOut: @escaping () -> Void) {
        self.profile = profile
        self.environment = environment
        self.onSignOut = onSignOut
        _listViewModel = State(initialValue: RoomsListViewModel(rooms: environment.rooms))
    }

    var body: some View {
        NavigationStack(path: $path) {
            RoomsListView(viewModel: listViewModel, path: $path)
                .navigationTitle("ImeTime")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Text(profile.displayName)
                            Button("登出", role: .destructive, action: onSignOut)
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                }
                .navigationDestination(for: HomeRoute.self) { route in
                    destination(for: route)
                }
        }
    }

    @ViewBuilder
    private func destination(for route: HomeRoute) -> some View {
        switch route {
        case .createRoom:
            if let createdRoom {
                RoomCreatedView(room: createdRoom) {
                    self.createdRoom = nil
                    path = [.room(createdRoom)]
                    Task { await listViewModel.load() }
                }
                // 滑動返回不會走上面的按鈕；createdRoom 還在就代表是這種情況，要清掉並補上列表更新
                .onDisappear {
                    guard self.createdRoom != nil else { return }
                    self.createdRoom = nil
                    Task { await listViewModel.load() }
                }
            } else {
                CreateRoomView(rooms: environment.rooms) { room in
                    createdRoom = room
                }
            }
        case .joinRoom:
            JoinRoomView(rooms: environment.rooms) { room in
                path = [.room(room)]
                Task { await listViewModel.load() }
            }
        case .room(let room):
            RoomView(room: room, currentUserID: profile.id, environment: environment, path: $path)
        case .roomSettings(let room):
            RoomSettingsView(room: room, currentUserID: profile.id, environment: environment) {
                path = []
                Task { await listViewModel.load() }
            }
        }
    }
}
