import Foundation
import Testing
@testable import NemiKit

@Suite("PKCE")
struct PKCETests {
    @Test("RFC 7636 appendix B test vector")
    func rfcVector() throws {
        let pkce = try PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(pkce.method == "S256")
    }

    @Test("random verifiers are 43 url-safe characters and unique")
    func randomVerifier() throws {
        let a = try PKCE()
        let b = try PKCE()
        #expect(a.verifier.count == 43)
        #expect(a.verifier != b.verifier)
        #expect(a.verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(!a.challenge.contains("="))
        #expect(a.challenge == PKCE.challenge(for: a.verifier))
    }

    @Test("too short verifiers are refused")
    func shortVerifier() {
        #expect(throws: NemiAuthError.self) { try PKCE(verifier: "short") }
    }
}

@Suite("Authorize URL and callback")
struct AuthorizeTests {
    let issuer = "https://nemi.test/oauth"
    let redirect = URL(string: "com.example.app:/callback")!

    func makeRequest(scopes: [NemiScope] = [.profile, .filesRead, .offlineAccess], prompt: String? = nil) throws -> NemiAuthorizationRequest {
        try NemiAuthorizationRequest.make(
            authorizationEndpoint: URL(string: "\(issuer)/authorize")!,
            clientId: "nemi_app_abc",
            redirectURI: redirect,
            scopes: scopes,
            pkce: try PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            state: "state+/=1",
            nonce: "nonce-1",
            prompt: prompt
        )
    }

    @Test("builds every required parameter")
    func parameters() throws {
        let request = try makeRequest(prompt: "consent")
        let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
        #expect(components.host == "nemi.test")
        #expect(components.path == "/oauth/authorize")
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(items["response_type"] == "code")
        #expect(items["client_id"] == "nemi_app_abc")
        #expect(items["redirect_uri"] == "com.example.app:/callback")
        #expect(items["scope"] == "openid profile files.read offline_access")
        #expect(items["state"] == "state+/=1")
        #expect(items["nonce"] == "nonce-1")
        #expect(items["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["prompt"] == "consent")
        // `+` must be escaped, or the server reads it as a space.
        #expect(request.url.absoluteString.contains("state=state%2B%2F%3D1"))
        #expect(request.url.absoluteString.contains("scope=openid%20profile"))
    }

    @Test("openid is added once and order is kept")
    func openidDeduplicated() throws {
        let request = try makeRequest(scopes: [.email, .openid, .email])
        #expect(request.scopes == [.openid, .email])
    }

    @Test("a valid callback yields the code")
    func validCallback() throws {
        let request = try makeRequest()
        let url = URL(string: "com.example.app:/callback?code=abc123&state=state%2B%2F%3D1&iss=https%3A%2F%2Fnemi.test%2Foauth")!
        #expect(try request.validateCallback(url, issuer: issuer) == "abc123")
    }

    @Test("state mismatch is refused")
    func stateMismatch() throws {
        let request = try makeRequest()
        let url = URL(string: "com.example.app:/callback?code=abc&state=other&iss=https%3A%2F%2Fnemi.test%2Foauth")!
        #expect(throws: NemiAuthError.stateMismatch) { try request.validateCallback(url, issuer: issuer) }
    }

    @Test("wrong or missing iss is refused")
    func issuerChecks() throws {
        let request = try makeRequest()
        let wrong = URL(string: "com.example.app:/callback?code=abc&state=state%2B%2F%3D1&iss=https%3A%2F%2Fevil.test")!
        #expect(throws: NemiAuthError.issuerMismatch(expected: issuer, received: "https://evil.test")) {
            try request.validateCallback(wrong, issuer: issuer)
        }
        let missing = URL(string: "com.example.app:/callback?code=abc&state=state%2B%2F%3D1")!
        #expect(throws: NemiAuthError.issuerMismatch(expected: issuer, received: nil)) {
            try request.validateCallback(missing, issuer: issuer)
        }
    }

    @Test("access_denied maps to its own case")
    func accessDenied() throws {
        let request = try makeRequest()
        let url = URL(string: "com.example.app:/callback?error=access_denied&state=state%2B%2F%3D1&iss=https%3A%2F%2Fnemi.test%2Foauth")!
        #expect(throws: NemiAuthError.accessDenied(description: nil)) {
            try request.validateCallback(url, issuer: issuer)
        }
    }

    @Test("the contract's deny redirect (no iss) maps to accessDenied")
    func contractDeny() throws {
        let request = try makeRequest()
        let url = URL(string: "com.example.app:/callback?error=access_denied&state=state%2B%2F%3D1")!
        #expect(throws: NemiAuthError.accessDenied(description: nil)) {
            try request.validateCallback(url, issuer: issuer)
        }
    }

    @Test("an error callback with a wrong iss is still an issuer mismatch")
    func errorWithWrongIssuer() throws {
        let request = try makeRequest()
        let url = URL(string: "com.example.app:/callback?error=access_denied&state=state%2B%2F%3D1&iss=https%3A%2F%2Fevil.test")!
        #expect(throws: NemiAuthError.issuerMismatch(expected: issuer, received: "https://evil.test")) {
            try request.validateCallback(url, issuer: issuer)
        }
    }

    @Test("revoke endpoint falls back to the token endpoint's sibling")
    func revokeFallback() {
        let document = NemiDiscoveryDocument(
            issuer: issuer, authorizationEndpoint: URL(string: "\(issuer)/authorize")!,
            tokenEndpoint: URL(string: "https://nemi.test/api/oauth/token")!, revocationEndpoint: nil,
            userinfoEndpoint: nil, jwksUri: URL(string: "\(issuer)/jwks")!
        )
        #expect(NemiAuth.revocationEndpoint(for: document)?.absoluteString == "https://nemi.test/api/oauth/revoke")
    }

    @Test("a callback on another URL is refused")
    func otherURL() throws {
        let request = try makeRequest()
        let url = URL(string: "com.other.app:/callback?code=abc&state=state%2B%2F%3D1")!
        #expect(throws: NemiAuthError.unexpectedCallbackURL) {
            try request.validateCallback(url, issuer: issuer)
        }
    }
}
