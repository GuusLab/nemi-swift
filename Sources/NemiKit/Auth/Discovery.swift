import Foundation

/// The parts of `/.well-known/openid-configuration` that NemiKit uses.
public struct NemiDiscoveryDocument: Codable, Sendable, Equatable {
    public let issuer: String
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let revocationEndpoint: URL?
    public let userinfoEndpoint: URL?
    public let jwksUri: URL
    public let scopesSupported: [String]?
    public let authorizationResponseIssParameterSupported: Bool?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case revocationEndpoint = "revocation_endpoint"
        case userinfoEndpoint = "userinfo_endpoint"
        case jwksUri = "jwks_uri"
        case scopesSupported = "scopes_supported"
        case authorizationResponseIssParameterSupported = "authorization_response_iss_parameter_supported"
    }

    public init(
        issuer: String,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        revocationEndpoint: URL?,
        userinfoEndpoint: URL?,
        jwksUri: URL,
        scopesSupported: [String]? = nil,
        authorizationResponseIssParameterSupported: Bool? = true
    ) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.revocationEndpoint = revocationEndpoint
        self.userinfoEndpoint = userinfoEndpoint
        self.jwksUri = jwksUri
        self.scopesSupported = scopesSupported
        self.authorizationResponseIssParameterSupported = authorizationResponseIssParameterSupported
    }

    /// `<issuer>/.well-known/openid-configuration`.
    public static func url(for issuer: URL) -> URL {
        issuer.appendingPathComponent(".well-known").appendingPathComponent("openid-configuration")
    }
}
