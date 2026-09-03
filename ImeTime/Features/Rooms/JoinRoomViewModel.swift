import Foundation
import ImeTimeCore
import Observation

@MainActor
@Observable
final class JoinRoomViewModel {
    var codeInput = ""
    private(set) var isJoining = false
    private(set) var errorMessage: String?

    private let rooms: any RoomRepository

    init(rooms: any RoomRepository) {
        self.rooms = rooms
    }

    var canSubmit: Bool {
        InviteCode(userInput: codeInput) != nil
    }

    func join() async -> Room? {
        errorMessage = nil
        guard let code = InviteCode(userInput: codeInput) else {
            errorMessage = "邀請碼是 6 個字母或數字。"
            return nil
        }

        isJoining = true
        defer { isJoining = false }
        do {
            return try await rooms.joinRoom(code: code)
        } catch let error as RoomError {
            errorMessage = error.userMessage
            return nil
        } catch {
            errorMessage = "加入失敗，請檢查網路後再試一次。"
            return nil
        }
    }
}
