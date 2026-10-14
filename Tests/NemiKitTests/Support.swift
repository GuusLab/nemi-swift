import CryptoKit
import Foundation
@testable import NemiKit

/// A URLProtocol that answers from a handler. Network suites run `.serialized`
/// under `NetworkTests` because the handler is process-wide.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Recorded: Sendable {
        let request: URLRequest
        let body: Data
    }

    typealias Handler = @Sendable (URLRequest, Data) throws -> (Int, [String: String], Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var recorded: [Recorded] = []
    nonisolated(unsafe) static var delay: TimeInterval = 0

    static func reset(_ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
        recorded = []
        delay = 0
    }

    static var requests: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static func count(path: String) -> Int {
        requests.filter { $0.request.url?.path == path }.count
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.readBody(request)
        Self.lock.lock()
        let handler = Self.handler
        Self.recorded.append(Recorded(request: request, body: body))
        let delay = Self.delay
        Self.lock.unlock()
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        do {
            guard let handler else { throw URLError(.notConnectedToInternet) }
            let (status, headers, data) = try handler(request, body)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

let jsonHeaders = ["Content-Type": "application/json"]

/// A fake issuer with a real P-256 key.
struct TestIssuer: Sendable {
    let issuer = "https://nemi.test/oauth"
    let clientId = "nemi_app_test123"
    let redirectURI = URL(string: "com.example.app:/callback")!
    let kid = "key-1"
    let key = P256.Signing.PrivateKey()

    var jwk: [String: Any] {
        let raw = key.publicKey.rawRepresentation // x || y
        return [
            "kty": "EC", "crv": "P-256", "kid": kid, "alg": "ES256", "use": "sig",
            "x": Base64URL.encode(raw.prefix(32)),
            "y": Base64URL.encode(raw.suffix(32)),
        ]
    }

    var nemiJWK: NemiJWK {
        let raw = key.publicKey.rawRepresentation
        return NemiJWK(kid: kid, x: Base64URL.encode(raw.prefix(32)), y: Base64URL.encode(raw.suffix(32)))
    }

    var discovery: [String: Any] {
        [
            "issuer": issuer,
            "authorization_endpoint": "\(issuer)/authorize",
            "token_endpoint": "https://nemi.test/api/oauth/token",
            "revocation_endpoint": "https://nemi.test/api/oauth/revoke",
            "userinfo_endpoint": "https://nemi.test/api/oauth/userinfo",
            "jwks_uri": "\(issuer)/jwks",
            "authorization_response_iss_parameter_supported": true,
        ]
    }

    func idToken(
        sub: String = "pairwise-sub",
        aud: Any? = nil,
        iss: String? = nil,
        nonce: String? = nil,
        exp: Date = Date().addingTimeInterval(600),
        accessToken: String? = nil,
        kid: String? = nil,
        signWith otherKey: P256.Signing.PrivateKey? = nil
    ) -> String {
        let header: [String: Any] = ["alg": "ES256", "typ": "JWT", "kid": kid ?? self.kid]
        var claims: [String: Any] = [
            "iss": iss ?? issuer,
            "aud": aud ?? clientId,
            "sub": sub,
            "iat": Int(Date().timeIntervalSince1970),
            "exp": Int(exp.timeIntervalSince1970),
            "auth_time": Int(Date().timeIntervalSince1970),
            "name": "Ada Lovelace",
            "preferred_username": "ada",
            "email": "ada@example.com",
            "email_verified": true,
        ]
        if let nonce { claims["nonce"] = nonce }
        if let accessToken {
            claims["at_hash"] = Base64URL.encode(Data(SHA256.hash(data: Data(accessToken.utf8))).prefix(16))
        }
        let input = Base64URL.encode(json(header)) + "." + Base64URL.encode(json(claims))
        let signature = try! (otherKey ?? key).signature(for: Data(input.utf8))
        return input + "." + Base64URL.encode(signature.rawRepresentation)
    }

    func makeAuth(store: any NemiTokenStore) -> NemiAuth {
        NemiAuth(
            clientId: clientId,
            redirectURI: redirectURI,
            issuer: URL(string: issuer)!,
            tokenStore: store,
            urlSession: MockURLProtocol.session(),
            now: { Date() }
        )
    }
}
