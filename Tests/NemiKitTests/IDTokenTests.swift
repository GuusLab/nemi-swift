import CryptoKit
import Foundation
import Testing
@testable import NemiKit

@Suite("id_token verification")
struct IDTokenTests {
    let fixture = TestIssuer()

    func verify(_ token: String, nonce: String? = "n-1", accessToken: String? = nil) throws -> NemiIDTokenClaims {
        try IDTokenVerifier.verify(
            token, keys: [fixture.nemiJWK], issuer: fixture.issuer, clientId: fixture.clientId,
            nonce: nonce, accessToken: accessToken
        )
    }

    @Test("a valid token verifies and exposes its claims")
    func valid() throws {
        let claims = try verify(fixture.idToken(nonce: "n-1", accessToken: "nemi_oat_x"), accessToken: "nemi_oat_x")
        #expect(claims.sub == "pairwise-sub")
        #expect(claims.aud == [fixture.clientId])
        #expect(claims.name == "Ada Lovelace")
        #expect(claims.preferredUsername == "ada")
        #expect(claims.emailVerified == true)
    }

    @Test("aud as an array is accepted")
    func audienceArray() throws {
        _ = try verify(fixture.idToken(aud: [fixture.clientId], nonce: "n-1"))
    }

    @Test("expired tokens are refused")
    func expired() {
        let token = fixture.idToken(nonce: "n-1", exp: Date().addingTimeInterval(-3600))
        #expect(throws: IDTokenValidationError.expired) { try verify(token) }
    }

    @Test("wrong audience is refused")
    func wrongAudience() {
        let token = fixture.idToken(aud: "nemi_app_somebody_else", nonce: "n-1")
        #expect(throws: IDTokenValidationError.audienceMismatch) { try verify(token) }
    }

    @Test("wrong nonce is refused")
    func wrongNonce() {
        #expect(throws: IDTokenValidationError.nonceMismatch) { try verify(fixture.idToken(nonce: "other")) }
        #expect(throws: IDTokenValidationError.nonceMismatch) { try verify(fixture.idToken(nonce: nil)) }
    }

    @Test("wrong issuer is refused")
    func wrongIssuer() {
        let token = fixture.idToken(iss: "https://evil.test", nonce: "n-1")
        #expect(throws: IDTokenValidationError.issuerMismatch("https://evil.test")) { try verify(token) }
    }

    @Test("a signature from another key is refused")
    func wrongKey() {
        let token = fixture.idToken(nonce: "n-1", signWith: P256.Signing.PrivateKey())
        #expect(throws: IDTokenValidationError.invalidSignature) { try verify(token) }
    }

    @Test("a tampered payload is refused")
    func tampered() {
        var parts = fixture.idToken(nonce: "n-1").split(separator: ".").map(String.init)
        var payload = try! JSONSerialization.jsonObject(with: Base64URL.decode(parts[1])!) as! [String: Any]
        payload["sub"] = "someone-else"
        parts[1] = Base64URL.encode(json(payload))
        #expect(throws: IDTokenValidationError.invalidSignature) { try verify(parts.joined(separator: ".")) }
    }

    @Test("unknown kid and bad alg are refused")
    func keyAndAlgorithm() {
        #expect(throws: IDTokenValidationError.unknownKey("nope")) { try verify(fixture.idToken(nonce: "n-1", kid: "nope")) }
        let header = Base64URL.encode(json(["alg": "none", "kid": fixture.kid]))
        let parts = fixture.idToken(nonce: "n-1").split(separator: ".")
        #expect(throws: IDTokenValidationError.unsupportedAlgorithm("none")) {
            try verify("\(header).\(parts[1]).\(parts[2])")
        }
    }

    @Test("at_hash must match the access token")
    func atHash() {
        let token = fixture.idToken(nonce: "n-1", accessToken: "nemi_oat_real")
        #expect(throws: IDTokenValidationError.accessTokenHashMismatch) { try verify(token, accessToken: "nemi_oat_other") }
    }

    @Test("JWK coordinates build a CryptoKit key")
    func jwkKey() throws {
        let key = try fixture.nemiJWK.p256PublicKey()
        #expect(key.rawRepresentation == fixture.key.publicKey.rawRepresentation)
    }
}
