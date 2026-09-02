import Foundation

public enum NameValidationError: Error, Equatable, Sendable {
    case empty
    case tooLong(max: Int)
}

/// 所有「使用者輸入的名稱」共用的驗證：去頭尾空白、不可空、字數上限（以 Character 計）。
public enum NameValidator {
    public static func validate(_ raw: String, maxLength: Int) throws(NameValidationError) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw .empty }
        if trimmed.count > maxLength { throw .tooLong(max: maxLength) }
        return trimmed
    }
}
