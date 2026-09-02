import Testing
@testable import ImeTime

@Suite struct AppleNonceTests {
    @Test func sha256HexMatchesKnownVector() {
        #expect(AppleNonce.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func randomNonceIsHexOfRequestedLength() {
        let nonce = AppleNonce.random(byteCount: 32)
        #expect(nonce.count == 64)
        #expect(nonce.allSatisfy { $0.isHexDigit })
    }

    @Test func randomNoncesDiffer() {
        #expect(AppleNonce.random() != AppleNonce.random())
    }
}
