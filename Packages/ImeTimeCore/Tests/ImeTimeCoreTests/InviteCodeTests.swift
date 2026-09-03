import Testing
@testable import ImeTimeCore

/// 可重現的亂數（SplitMix64），只給測試用。
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct InviteCodeTests {
    @Test func alphabetExcludesAmbiguousCharacters() {
        for forbidden in ["0", "O", "1", "I"] {
            #expect(!InviteCode.alphabet.contains(forbidden))
        }
        #expect(InviteCode.alphabet.count == 32)
    }

    @Test func normalizesLowercaseSpacesAndDashes() {
        #expect(InviteCode(userInput: " ab c-d2 3 ")?.value == "ABCD23")
    }

    @Test func rejectsWrongLength() {
        #expect(InviteCode(userInput: "ABCDE") == nil)
        #expect(InviteCode(userInput: "ABCDEFG") == nil)
    }

    @Test func rejectsCharactersOutsideAlphabet() {
        #expect(InviteCode(userInput: "ABCDE0") == nil)
        #expect(InviteCode(userInput: "ABCDEO") == nil)
        #expect(InviteCode(userInput: "ABCDE1") == nil)
        #expect(InviteCode(userInput: "ABCDEI") == nil)
    }

    @Test func exactInitRequiresAlreadyNormalizedValue() {
        #expect(InviteCode(exact: "ABCD23")?.value == "ABCD23")
        #expect(InviteCode(exact: "abcd23") == nil)
    }

    @Test func generatedCodeIsValid() {
        let code = InviteCode.generate()
        #expect(InviteCode(userInput: code.value) == code)
    }

    @Test func generationIsDeterministicForSameSeed() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        #expect(InviteCode.generate(using: &a) == InviteCode.generate(using: &b))
    }
}
