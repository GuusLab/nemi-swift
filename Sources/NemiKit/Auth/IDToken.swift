import CryptoKit
import Foundation

/// One key from the issuer's JWKS. Nemi signs with EC P-256 (ES256).
public struct NemiJWK: Codable, Sendable, Equatable {
    public let kty: String
    public let crv: String?
    public let kid: String?
    public let alg: String?
    public let use: String?
    public let x: String?
    public let y: String?

    public init(kty: String = "EC", crv: String? = "P-256", kid: String?, alg: String? = "ES256", use: String? = "sig", x: String?, y: String?) {
        self.kty = kty
        self.crv = crv
        self.kid = kid
        self.alg = alg
        self.use = use
        self.x = x
        self.y = y
    }

    /// Builds the CryptoKit key from the base64url `x` and `y` coordinates.
    public func p256PublicKey() throws -> P256.Signing.PublicKey {
        guard kty == "EC", crv == nil || crv == "P-256",
              let xString = x, let yString = y,
              let xData = Base64URL.decode(xString), let yData = Base64URL.decode(yString),
              xData.count <= 32, yData.count <= 32 else {
            throw IDTokenValidationError.unknownKey(kid)
        }
        // Coordinates are fixed-length 32 bytes; left-pad in case a producer trimmed leading zeros.
        let raw = Data(repeating: 0, count: 32 - xData.count) + xData
            + Data(repeating: 0, count: 32 - yData.count) + yData
        do {
            return try P256.Signing.PublicKey(rawRepresentation: raw)
        } catch {
            throw IDTokenValidationError.unknownKey(kid)
        }
    }
}

/// A JSON Web Key Set.
public struct NemiJWKSet: Codable, Sendable, Equatable {
    public let keys: [NemiJWK]
    public init(keys: [NemiJWK]) { self.keys = keys }
}

/// The claims of a verified Nemi id_token.
public struct NemiIDTokenClaims: Codable, Sendable, Equatable {
    public let iss: String
    /// Pairwise subject: stable for one developer, different between developers.
    public let sub: String
    public let aud: [String]
    public let exp: Date
    public let iat: Date?
    public let authTime: Date?
    public let nonce: String?
    public let atHash: String?
    public let azp: String?
    public let name: String?
    public let preferredUsername: String?
    public let picture: URL?
    public let email: String?
    public let emailVerified: Bool?

    enum CodingKeys: String, CodingKey {
        case iss, sub, aud, exp, iat, nonce, azp, name, picture, email
        case authTime = "auth_time"
        case atHash = "at_hash"
        case preferredUsername = "preferred_username"
        case emailVerified = "email_verified"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        iss = try c.decode(String.self, forKey: .iss)
        sub = try c.decode(String.self, forKey: .sub)
        if let single = try? c.decode(String.self, forKey: .aud) {
            aud = [single]
        } else {
            aud = try c.decode([String].self, forKey: .aud)
        }
        exp = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .exp))
        iat = try c.decodeIfPresent(Double.self, forKey: .iat).map(Date.init(timeIntervalSince1970:))
        authTime = try c.decodeIfPresent(Double.self, forKey: .authTime).map(Date.init(timeIntervalSince1970:))
        nonce = try c.decodeIfPresent(String.self, forKey: .nonce)
        atHash = try c.decodeIfPresent(String.self, forKey: .atHash)
        azp = try c.decodeIfPresent(String.self, forKey: .azp)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        preferredUsername = try c.decodeIfPresent(String.self, forKey: .preferredUsername)
        picture = try? c.decodeIfPresent(URL.self, forKey: .picture)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        emailVerified = try c.decodeIfPresent(Bool.self, forKey: .emailVerified)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(iss, forKey: .iss)
        try c.encode(sub, forKey: .sub)
        try c.encode(aud, forKey: .aud)
        try c.encode(exp.timeIntervalSince1970, forKey: .exp)
        try c.encodeIfPresent(iat?.timeIntervalSince1970, forKey: .iat)
        try c.encodeIfPresent(authTime?.timeIntervalSince1970, forKey: .authTime)
        try c.encodeIfPresent(nonce, forKey: .nonce)
        try c.encodeIfPresent(atHash, forKey: .atHash)
        try c.encodeIfPresent(azp, forKey: .azp)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(preferredUsername, forKey: .preferredUsername)
        try c.encodeIfPresent(picture, forKey: .picture)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encodeIfPresent(emailVerified, forKey: .emailVerified)
    }
}

/// Verifies Nemi id_tokens: ES256 signature, `iss`, `aud`, `exp`, `nonce` and `at_hash`.
public enum IDTokenVerifier {
    struct Header: Decodable {
        let alg: String?
        let kid: String?
        let typ: String?
    }

    /// Returns the `kid` from the token header without verifying anything.
    public static func keyID(of token: String) throws -> String? {
        try decodeHeader(token).kid
    }

    /// Verifies `token` and returns its claims.
    ///
    /// - Parameters:
    ///   - keys: the issuer's JWKS keys.
    ///   - issuer: the expected `iss`.
    ///   - clientId: must be in `aud`.
    ///   - nonce: the nonce sent on the authorize request. `nil` skips the check (refresh responses).
    ///   - accessToken: when given and the token has `at_hash`, the hash is checked.
    ///   - now: the current time.
    ///   - leeway: allowed clock skew in seconds.
    public static func verify(
        _ token: String,
        keys: [NemiJWK],
        issuer: String,
        clientId: String,
        nonce: String?,
        accessToken: String? = nil,
        now: Date = Date(),
        leeway: TimeInterval = 120
    ) throws -> NemiIDTokenClaims {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw IDTokenValidationError.malformed }

        let header = try decodeHeader(token)
        guard header.alg == "ES256" else { throw IDTokenValidationError.unsupportedAlgorithm(header.alg) }

        let candidates: [NemiJWK]
        if let kid = header.kid {
            candidates = keys.filter { $0.kid == kid }
        } else {
            candidates = keys.filter { $0.kty == "EC" }
        }
        guard !candidates.isEmpty else { throw IDTokenValidationError.unknownKey(header.kid) }

        // JOSE ES256 signatures are the raw 64-byte r || s, not DER.
        guard let signatureData = Base64URL.decode(String(parts[2])), signatureData.count == 64,
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData) else {
            throw IDTokenValidationError.invalidSignature
        }
        // `isValidSignature(_:for: Data)` hashes with SHA-256 itself; do not pre-hash.
        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        let valid = try candidates.contains { key in
            try key.p256PublicKey().isValidSignature(signature, for: signingInput)
        }
        guard valid else { throw IDTokenValidationError.invalidSignature }

        guard let payload = Base64URL.decode(String(parts[1])),
              let claims = try? JSONDecoder().decode(NemiIDTokenClaims.self, from: payload) else {
            throw IDTokenValidationError.malformed
        }

        guard claims.iss == issuer else { throw IDTokenValidationError.issuerMismatch(claims.iss) }
        guard claims.aud.contains(clientId) else { throw IDTokenValidationError.audienceMismatch }
        if claims.aud.count > 1, let azp = claims.azp, azp != clientId {
            throw IDTokenValidationError.audienceMismatch
        }
        guard claims.exp.addingTimeInterval(leeway) > now else { throw IDTokenValidationError.expired }
        if let iat = claims.iat, iat.addingTimeInterval(-leeway) > now {
            throw IDTokenValidationError.issuedInFuture
        }
        if let nonce {
            guard let claimed = claims.nonce, constantTimeEquals(claimed, nonce) else {
                throw IDTokenValidationError.nonceMismatch
            }
        }
        if let accessToken, let atHash = claims.atHash {
            let digest = Data(SHA256.hash(data: Data(accessToken.utf8)))
            let expected = Base64URL.encode(digest.prefix(16))
            guard constantTimeEquals(expected, atHash) else {
                throw IDTokenValidationError.accessTokenHashMismatch
            }
        }
        return claims
    }

    static func decodeHeader(_ token: String) throws -> Header {
        guard let first = token.split(separator: ".", omittingEmptySubsequences: false).first,
              let data = Base64URL.decode(String(first)),
              let header = try? JSONDecoder().decode(Header.self, from: data) else {
            throw IDTokenValidationError.malformed
        }
        return header
    }
}

func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
    let a = Array(lhs.utf8)
    let b = Array(rhs.utf8)
    guard a.count == b.count else { return false }
    var difference: UInt8 = 0
    for index in a.indices { difference |= a[index] ^ b[index] }
    return difference == 0
}
