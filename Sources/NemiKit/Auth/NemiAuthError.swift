import Foundation

/// Errors from signing in, refreshing and signing out.
public enum NemiAuthError: Error, Sendable, Equatable {
    /// The person closed the sign-in sheet. Usually not worth showing an error for.
    case cancelled
    /// The person declined on the consent screen (`error=access_denied`).
    case accessDenied(description: String?)
    /// The authorize endpoint redirected back with another OAuth error.
    case authorizationFailed(error: String, description: String?)
    /// The `state` in the callback does not match the one that was sent.
    case stateMismatch
    /// The `iss` in the callback, or the discovery document's `issuer`, is not the configured issuer.
    case issuerMismatch(expected: String, received: String?)
    /// The callback URL had no `code`.
    case missingAuthorizationCode
    /// The callback URL does not belong to the configured redirect URI.
    case unexpectedCallbackURL
    /// The token endpoint refused the request (RFC 6749 error body).
    case tokenRequestFailed(status: Int, error: String, description: String?)
    /// The token endpoint answered with something that is not a token response.
    case invalidTokenResponse
    /// The id_token failed verification.
    case invalidIDToken(IDTokenValidationError)
    /// The discovery document or JWKS could not be fetched or read.
    case discoveryFailed(String)
    /// There is no stored session. Call `signIn` first.
    case notSignedIn
    /// The refresh token was rejected (expired, revoked or reused). The stored session was cleared.
    case sessionExpired
    /// The web authentication sheet could not be shown, or is not available on this platform.
    case presentationFailed(String)
    /// The `NemiAuth` setup is invalid.
    case invalidConfiguration(String)
    /// The token store failed to read or write.
    case storageFailed(String)
    /// A network error.
    case network(String)
}

extension NemiAuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cancelled: return "Sign in was cancelled."
        case .accessDenied(let description): return description ?? "Access was denied."
        case .authorizationFailed(let error, let description): return description ?? "Authorization failed (\(error))."
        case .stateMismatch: return "The sign-in response did not match the request (state)."
        case .issuerMismatch(let expected, let received): return "Unexpected issuer \(received ?? "(none)"), expected \(expected)."
        case .missingAuthorizationCode: return "The sign-in response had no authorization code."
        case .unexpectedCallbackURL: return "The sign-in response came back on an unexpected URL."
        case .tokenRequestFailed(let status, let error, let description): return description ?? "Token request failed with \(error) (HTTP \(status))."
        case .invalidTokenResponse: return "The token response could not be read."
        case .invalidIDToken(let reason): return "The id_token is invalid: \(reason)."
        case .discoveryFailed(let message): return "Could not load the Nemi sign-in configuration: \(message)"
        case .notSignedIn: return "Not signed in with Nemi."
        case .sessionExpired: return "The Nemi session has expired. Sign in again."
        case .presentationFailed(let message): return "Could not show Sign in with Nemi: \(message)"
        case .invalidConfiguration(let message): return message
        case .storageFailed(let message): return "Could not access the stored Nemi session: \(message)"
        case .network(let message): return message
        }
    }
}

/// Why an id_token was refused.
public enum IDTokenValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case malformed
    case unsupportedAlgorithm(String?)
    case unknownKey(String?)
    case invalidSignature
    case issuerMismatch(String)
    case audienceMismatch
    case expired
    case issuedInFuture
    case nonceMismatch
    case accessTokenHashMismatch

    public var description: String {
        switch self {
        case .malformed: return "malformed token"
        case .unsupportedAlgorithm(let alg): return "unsupported algorithm \(alg ?? "(none)")"
        case .unknownKey(let kid): return "unknown signing key \(kid ?? "(none)")"
        case .invalidSignature: return "invalid signature"
        case .issuerMismatch(let iss): return "unexpected issuer \(iss)"
        case .audienceMismatch: return "audience does not contain this client"
        case .expired: return "token expired"
        case .issuedInFuture: return "token issued in the future"
        case .nonceMismatch: return "nonce mismatch"
        case .accessTokenHashMismatch: return "at_hash does not match the access token"
        }
    }
}
