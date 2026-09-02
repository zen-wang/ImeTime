import Foundation
import Testing
@testable import ImeTime

/// 用假的 Info.plist 值驅動 AppConfig.load，不依賴實際 xcconfig 注入的內容。
private final class StubBundle: Bundle, @unchecked Sendable {
    private let values: [String: Any]

    init(values: [String: Any]) {
        self.values = values
        super.init()
    }

    override func object(forInfoDictionaryKey key: String) -> Any? {
        values[key]
    }
}

@Suite struct AppConfigTests {
    @Test func loadsURLAndKey() throws {
        let bundle = StubBundle(values: [
            "SupabaseURL": "http://127.0.0.1:54321",
            "SupabaseAnonKey": "anon-key",
        ])

        let config = try AppConfig.load(bundle: bundle)

        #expect(config.supabaseURL == URL(string: "http://127.0.0.1:54321"))
        #expect(config.supabaseAnonKey == "anon-key")
    }

    @Test func emptyKeyThrowsMissingAnonKey() {
        let bundle = StubBundle(values: [
            "SupabaseURL": "http://127.0.0.1:54321",
            "SupabaseAnonKey": "",
        ])

        #expect(throws: AppConfigError.missingAnonKey) {
            try AppConfig.load(bundle: bundle)
        }
    }

    @Test func nonHTTPSchemeThrowsInvalidURL() {
        let bundle = StubBundle(values: [
            "SupabaseURL": "ftp://example.com",
            "SupabaseAnonKey": "anon-key",
        ])

        #expect(throws: AppConfigError.invalidSupabaseURL("ftp://example.com")) {
            try AppConfig.load(bundle: bundle)
        }
    }

    @Test func emptyURLThrowsInvalidURL() {
        let bundle = StubBundle(values: [
            "SupabaseURL": "",
            "SupabaseAnonKey": "anon-key",
        ])

        #expect(throws: AppConfigError.invalidSupabaseURL("")) {
            try AppConfig.load(bundle: bundle)
        }
    }
}
