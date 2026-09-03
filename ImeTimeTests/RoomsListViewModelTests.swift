import Foundation
import ImeTimeCore
import Testing
@testable import ImeTime

@MainActor
@Suite struct RoomsListViewModelTests {
    @Test func startsLoading() {
        let sut = RoomsListViewModel(rooms: FakeRoomRepository())
        #expect(sut.state == .loading)
    }

    @Test func emptyListShowsEmptyState() async {
        let sut = RoomsListViewModel(rooms: FakeRoomRepository())
        await sut.load()
        #expect(sut.state == .empty)
    }

    @Test func loadedListKeepsServerOrder() async {
        let rooms = FakeRoomRepository()
        let first = RoomSummary(room: FakeRoomRepository.makeRoom(name: "先"), memberCount: 2)
        let second = RoomSummary(room: FakeRoomRepository.makeRoom(name: "後"), memberCount: 5)
        await rooms.set(summaries: [first, second])
        let sut = RoomsListViewModel(rooms: rooms)
        await sut.load()
        #expect(sut.state == .loaded([first, second]))
    }

    @Test func failureShowsMessage() async {
        let rooms = FakeRoomRepository()
        await rooms.fail(with: FakeError())
        let sut = RoomsListViewModel(rooms: rooms)
        await sut.load()
        #expect(sut.state == .failed("無法載入房間，請檢查網路後再試。"))
    }
}
