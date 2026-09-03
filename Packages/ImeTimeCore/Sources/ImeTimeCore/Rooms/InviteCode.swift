/// 房間邀請碼：6 碼，字母表排除 0/O/1/I。與 SQL 的 generate_invite_code() 使用同一字母表。
public struct InviteCode: Equatable, Hashable, Sendable, CustomStringConvertible {
    public static let length = 6
    public static let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    public let value: String

    /// 使用者輸入：忽略大小寫、空白與連字號。
    public init?(userInput: String) {
        let cleaned = userInput.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        self.init(exact: cleaned)
    }

    /// 已正規化的值（例如伺服器回傳）。
    public init?(exact: String) {
        guard exact.count == Self.length,
              exact.allSatisfy({ Self.alphabet.contains($0) })
        else { return nil }
        value = exact
    }

    public static func generate(using generator: inout some RandomNumberGenerator) -> InviteCode {
        let letters = Array(alphabet)
        var result = ""
        for _ in 0..<length {
            let index = Int.random(in: 0..<letters.count, using: &generator)
            result.append(letters[index])
        }
        return InviteCode(exact: result)!
    }

    public static func generate() -> InviteCode {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    public var description: String { value }
}
