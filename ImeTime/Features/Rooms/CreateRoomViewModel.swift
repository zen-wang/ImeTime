import Foundation
import ImeTimeCore
import Observation

@MainActor
@Observable
final class CreateRoomViewModel {
    var nameInput = ""
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private let rooms: any RoomRepository
    private let timeZoneID: String

    init(rooms: any RoomRepository, timeZoneID: String = TimeZone.current.identifier) {
        self.rooms = rooms
        self.timeZoneID = timeZoneID
    }

    func create() async -> Room? {
        errorMessage = nil
        let name: RoomName
        do {
            name = try RoomName(nameInput)
        } catch {
            errorMessage = error.userMessage
            return nil
        }

        isSaving = true
        defer { isSaving = false }
        do {
            return try await rooms.createRoom(name: name, timeZoneID: timeZoneID)
        } catch let error as RoomError {
            errorMessage = error.userMessage
            return nil
        } catch {
            errorMessage = "建立失敗，請檢查網路後再試一次。"
            return nil
        }
    }
}

/// 邀請文字（分享表用）。TestFlight 連結在 P6 加入。
enum InviteShare {
    static func text(for room: Room) -> String {
        "來加入我的 ImeTime 房間「\(room.name)」！邀請碼：\(room.inviteCode)（在 ImeTime 首頁選「用邀請碼加入」輸入）"
    }
}
