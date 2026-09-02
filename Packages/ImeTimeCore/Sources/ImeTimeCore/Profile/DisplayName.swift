/// 個人檔案顯示名稱，對應 profiles.display_name（1...20 字）。
public struct DisplayName: Equatable, Sendable {
    public static let maxLength = 20
    public let value: String

    public init(_ raw: String) throws(NameValidationError) {
        value = try NameValidator.validate(raw, maxLength: Self.maxLength)
    }
}
