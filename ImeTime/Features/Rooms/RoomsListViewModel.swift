import Foundation
import ImeTimeCore
import Observation

@MainActor
@Observable
final class RoomsListViewModel {
    enum State: Equatable {
        case loading
        case empty
        case loaded([RoomSummary])
        case failed(String)
    }

    private(set) var state: State = .loading
    private let rooms: any RoomRepository

    init(rooms: any RoomRepository) {
        self.rooms = rooms
    }

    func load() async {
        do {
            let list = try await rooms.myRooms()
            state = list.isEmpty ? .empty : .loaded(list)
        } catch {
            state = .failed("無法載入房間，請檢查網路後再試。")
        }
    }
}
