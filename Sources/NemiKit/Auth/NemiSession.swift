import Foundation

/// The tokens for one signed-in person, as stored by a `NemiTokenStore`.
public struct NemiSession: Codable, Sendable, Equatable {
    /// `nemi_oat_...`. Sent as `Authorization: Bearer`.
    public var accessToken: String
    /// `nemi_ort_...`. Present when `offline_access` was granted. Rotates on every refresh.
    public var refreshToken: String?
    /// The raw id_token from the last token response that carried one.
    public var idToken: String?
    /// Usually `Bearer`.
    public var tokenType: String
    /// The scopes that were actually granted.
    public var scopes: [NemiScope]
    /// When the access token stops working.
    public var expiresAt: Date
    /// Verified claims from the id_token (with `openid`).
    public var user: NemiIDTokenClaims?

    public init(
        accessToken: String,
        refreshToken: String?,
        idToken: String?,
        tokenType: String = "Bearer",
        scopes: [NemiScope],
        expiresAt: Date,
        user: NemiIDTokenClaims?
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.tokenType = tokenType
        self.scopes = scopes
        self.expiresAt = expiresAt
        self.user = user
    }

    /// True when the access token expires within `leeway` seconds of `now`.
    public func isExpired(at now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) <= leeway
    }

    /// Whether `scope` was granted.
    public func hasScope(_ scope: NemiScope) -> Bool { scopes.contains(scope) }
}

/// The token endpoint's JSON (RFC 6749 section 5.1).
struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let tokenType: String?
    let expiresIn: Double?
    let refreshToken: String?
    let scope: String?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case idToken = "id_token"
    }
}

/// RFC 6749 section 5.2 error body.
struct OAuthErrorResponse: Decodable, Sendable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
