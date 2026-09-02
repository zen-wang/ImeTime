import Foundation
import Supabase
import Testing
@testable import ImeTime

@Suite struct AuthStateMapperTests {
    let uid = UUID()

    @Test func initialSessionWithoutUserIsSignedOut() {
        #expect(AuthStateMapper.map(event: .initialSession, userID: nil) == .signedOut)
    }

    @Test func initialSessionWithUserIsSignedIn() {
        #expect(AuthStateMapper.map(event: .initialSession, userID: uid) == .signedIn(userID: uid))
    }

    @Test func signedInEventIsSignedIn() {
        #expect(AuthStateMapper.map(event: .signedIn, userID: uid) == .signedIn(userID: uid))
    }

    @Test func tokenRefreshedKeepsSignedIn() {
        #expect(AuthStateMapper.map(event: .tokenRefreshed, userID: uid) == .signedIn(userID: uid))
    }

    @Test func signedOutEventIsSignedOut() {
        #expect(AuthStateMapper.map(event: .signedOut, userID: nil) == .signedOut)
    }

    @Test func userDeletedIsSignedOut() {
        #expect(AuthStateMapper.map(event: .userDeleted, userID: uid) == .signedOut)
    }

    @Test func passwordRecoveryIsIgnored() {
        #expect(AuthStateMapper.map(event: .passwordRecovery, userID: uid) == nil)
    }

    @Test func userUpdatedKeepsSignedIn() {
        #expect(AuthStateMapper.map(event: .userUpdated, userID: uid) == .signedIn(userID: uid))
    }

    @Test func signedInWithoutUserIsIgnored() {
        #expect(AuthStateMapper.map(event: .signedIn, userID: nil) == nil)
    }
}
