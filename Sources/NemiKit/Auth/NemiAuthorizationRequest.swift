import Foundation

/// One pending sign-in: the authorize URL plus the secrets needed to finish it.
///
/// `NemiAuth.signIn` handles this for you. Use it directly when you present the
/// authorize URL yourself (for example on a platform without
/// `ASWebAuthenticationSession`), then pass the callback URL to
/// `NemiAuth.completeAuthorization(callbackURL:request:)`.
public struct NemiAuthorizationRequest: Sendable, Equatable {
    /// Open this URL in a browser.
    public let url: URL
    public let state: String
    public let nonce: String
    public let pkce: PKCE
    public let redirectURI: URL
    public let scopes: [NemiScope]

    /// Builds the authorize URL. `openid` is added when missing.
    public static func make(
        authorizationEndpoint: URL,
        clientId: String,
        redirectURI: URL,
        scopes: [NemiScope],
        pkce: PKCE,
        state: String,
        nonce: String,
        prompt: NemiPrompt? = nil
    ) throws -> NemiAuthorizationRequest {
        var finalScopes: [NemiScope] = []
        for scope in [NemiScope.openid] + scopes where !finalScopes.contains(scope) {
            finalScopes.append(scope)
        }

        guard var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw NemiAuthError.invalidConfiguration("Invalid authorization endpoint \(authorizationEndpoint).")
        }
        var items = components.queryItems ?? []
        items += [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: finalScopes.map(\.rawValue).joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        if let prompt { items.append(URLQueryItem(name: "prompt", value: prompt.rawValue)) }
        // Escape everything outside the unreserved set so `+`, `:` and `/` survive intact.
        components.percentEncodedQuery = items
            .map { "\(FormEncoding.escape($0.name))=\(FormEncoding.escape($0.value ?? ""))" }
            .joined(separator: "&")
        guard let url = components.url else {
            throw NemiAuthError.invalidConfiguration("Could not build the authorize URL.")
        }
        return NemiAuthorizationRequest(
            url: url, state: state, nonce: nonce, pkce: pkce, redirectURI: redirectURI, scopes: finalScopes
        )
    }

    /// Checks a callback URL against this request and returns the authorization code.
    ///
    /// `state` must match. A wrong `iss` is always refused. A successful callback
    /// must carry `iss` (RFC 9207, and every Nemi approve redirect does); an error
    /// callback such as `error=access_denied` may leave it out.
    ///
    /// - Parameter issuer: the expected `iss`.
    public func validateCallback(_ callbackURL: URL, issuer: String) throws -> String {
        guard matchesRedirectURI(callbackURL) else { throw NemiAuthError.unexpectedCallbackURL }
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }

        // State first: an error response for somebody else's request must not be trusted either.
        guard let returnedState = value("state"), constantTimeEquals(returnedState, state) else {
            throw NemiAuthError.stateMismatch
        }
        let iss = value("iss")
        if let iss, iss != issuer {
            throw NemiAuthError.issuerMismatch(expected: issuer, received: iss)
        }
        if let error = value("error") {
            let description = value("error_description")
            if error == "access_denied" { throw NemiAuthError.accessDenied(description: description) }
            throw NemiAuthError.authorizationFailed(error: error, description: description)
        }
        guard iss != nil else { throw NemiAuthError.issuerMismatch(expected: issuer, received: nil) }
        guard let code = value("code"), !code.isEmpty else { throw NemiAuthError.missingAuthorizationCode }
        return code
    }

    private func matchesRedirectURI(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == redirectURI.scheme?.lowercased() else { return false }
        if let host = redirectURI.host, host.lowercased() != url.host?.lowercased() { return false }
        if redirectURI.port != url.port { return false }
        return normalizedPath(url) == normalizedPath(redirectURI)
    }

    private func normalizedPath(_ url: URL) -> String {
        // `com.example.app:/callback` has no host, so read the path from the components.
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? url.path
        return path.isEmpty ? "/" : path
    }
}
