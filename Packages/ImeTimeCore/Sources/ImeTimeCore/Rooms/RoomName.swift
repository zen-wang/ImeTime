/// 房間名稱，對應 rooms.name（1...30 字）。
public struct RoomName: Equatable, Sendable {
    public static let maxLength = 30
    public let value: String

    public init(_ raw: String) throws(NameValidationError) {
        value = try NameValidator.validate(raw, maxLength: Self.maxLength)
    }
}
