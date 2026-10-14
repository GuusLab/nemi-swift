import Foundation

/// Sign in with Nemi: OAuth 2.0 authorization code flow with PKCE, OpenID Connect
/// id_token verification, token storage and automatic refresh.
///
/// ```swift
/// let auth = NemiAuth(
///     clientId: "nemi_app_...",
///     redirectURI: URL(string: "com.example.app:/callback")!
/// )
/// let session = try await auth.signIn(scopes: [.profile, .email, .offlineAccess, .filesRead])
/// ```
///
/// `NemiAuth` is safe to share across tasks. Keep one instance for the app.
public final class NemiAuth: NemiAccessTokenProvider, Sendable {
    public let clientId: String
    public let redirectURI: URL
    public let issuer: URL
    public let tokenStore: any NemiTokenStore

    let transport: HTTPTransport
    let state: AuthState
    let now: @Sendable () -> Date

    /// - Parameters:
    ///   - clientId: your app's `nemi_app_...` client ID.
    ///   - redirectURI: one of the app's registered redirect URIs, for example
    ///     `com.example.app:/callback` or `https://example.com/nemi/callback`.
    ///   - issuer: the OIDC issuer. Defaults to `https://nemilab.com/oauth`.
    ///   - tokenStore: where the session is kept. Defaults to the Keychain.
    ///   - urlSession: the session used for every request.
    public convenience init(
        clientId: String,
        redirectURI: URL,
        issuer: URL = NemiKit.defaultIssuer,
        tokenStore: (any NemiTokenStore)? = nil,
        urlSession: URLSession = .shared
    ) {
        self.init(
            clientId: clientId,
            redirectURI: redirectURI,
            issuer: issuer,
            tokenStore: tokenStore ?? NemiAuth.defaultTokenStore(clientId: clientId),
            urlSession: urlSession,
            now: { Date() }
        )
    }

    init(
        clientId: String,
        redirectURI: URL,
        issuer: URL,
        tokenStore: any NemiTokenStore,
        urlSession: URLSession,
        now: @escaping @Sendable () -> Date
    ) {
        self.clientId = clientId
        self.redirectURI = redirectURI
        // The issuer is compared as a string, so drop a trailing slash once here.
        var issuerString = issuer.absoluteString
        while issuerString.hasSuffix("/") { issuerString.removeLast() }
        self.issuer = URL(string: issuerString) ?? issuer
        self.tokenStore = tokenStore
        self.transport = HTTPTransport(session: urlSession)
        self.now = now
        self.state = AuthState(store: tokenStore)
    }

    private static func defaultTokenStore(clientId: String) -> any NemiTokenStore {
        #if canImport(Security)
        return KeychainTokenStore(service: "com.nemilab.nemikit", account: clientId)
        #else
        return InMemoryTokenStore()
        #endif
    }

    var issuerString: String { issuer.absoluteString }

    // MARK: Discovery

    /// The issuer's discovery document, fetched once and cached for a day.
    public func discovery() async throws -> NemiDiscoveryDocument {
        if let cached = await state.cachedDiscovery(now: now()) { return cached }
        let document = try await fetchDiscovery()
        await state.storeDiscovery(document, now: now())
        return document
    }

    private func fetchDiscovery() async throws -> NemiDiscoveryDocument {
        var request = URLRequest(url: NemiDiscoveryDocument.url(for: issuer))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(nemiUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw NemiAuthError.discoveryFailed("HTTP \(response.statusCode)")
        }
        let document: NemiDiscoveryDocument
        do {
            document = try JSONDecoder().decode(NemiDiscoveryDocument.self, from: data)
        } catch {
            throw NemiAuthError.discoveryFailed("The discovery document could not be read.")
        }
        var advertised = document.issuer
        while advertised.hasSuffix("/") { advertised.removeLast() }
        guard advertised == issuerString else {
            throw NemiAuthError.issuerMismatch(expected: issuerString, received: document.issuer)
        }
        return document
    }

    /// Signing keys. A token whose `kid` is unknown triggers one refetch, to pick up key rotation.
    func signingKeys(for token: String) async throws -> [NemiJWK] {
        let kid = try? IDTokenVerifier.keyID(of: token)
        if let cached = await state.cachedKeys(now: now()),
           kid == nil || cached.contains(where: { $0.kid == kid }) {
            return cached
        }
        let document = try await discovery()
        var request = URLRequest(url: document.jwksUri)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(nemiUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode),
              let set = try? JSONDecoder().decode(NemiJWKSet.self, from: data) else {
            throw NemiAuthError.discoveryFailed("The signing keys (JWKS) could not be loaded.")
        }
        await state.storeKeys(set.keys, now: now())
        return set.keys
    }

    // MARK: Authorization

    /// Creates the authorize URL and the secrets (PKCE verifier, state, nonce) for one sign-in.
    ///
    /// - Parameter prompt: pass `"consent"` to always show the consent screen.
    public func makeAuthorizationRequest(
        scopes: [NemiScope] = NemiScope.defaultSignIn,
        prompt: String? = nil
    ) async throws -> NemiAuthorizationRequest {
        let document = try await discovery()
        return try NemiAuthorizationRequest.make(
            authorizationEndpoint: document.authorizationEndpoint,
            clientId: clientId,
            redirectURI: redirectURI,
            scopes: scopes,
            pkce: try PKCE(),
            state: try SecureRandom.token(),
            nonce: try SecureRandom.token(),
            prompt: prompt
        )
    }

    /// Finishes a sign-in: validates the callback (`state`, `iss`, errors),
    /// exchanges the code, verifies the id_token and stores the session.
    @discardableResult
    public func completeAuthorization(callbackURL: URL, request: NemiAuthorizationRequest) async throws -> NemiSession {
        let document = try await discovery()
        let code = try request.validateCallback(callbackURL, issuer: issuerString)
        let response = try await tokenRequest(document: document, parameters: [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", request.redirectURI.absoluteString),
            ("code_verifier", request.pkce.verifier),
            ("client_id", clientId),
        ])
        let session = try await makeSession(from: response, previous: nil, nonce: request.nonce, requireIDToken: request.scopes.contains(.openid))
        try await state.replace(with: session)
        return session
    }

    // MARK: Session

    /// The stored session, if any. Does not refresh.
    public func currentSession() async throws -> NemiSession? {
        try await state.session()
    }

    /// A valid access token, refreshed first when it expires within a minute.
    /// Concurrent callers share one refresh.
    public func accessToken() async throws -> String {
        try await validSession().accessToken
    }

    /// The stored session, refreshed first when its access token expires within a minute.
    public func validSession() async throws -> NemiSession {
        try await state.validSession(now: now) { [self] previous in
            try await performRefresh(previous)
        }
    }

    /// Forces a refresh, even when the access token is still valid.
    @discardableResult
    public func refresh() async throws -> NemiSession {
        try await state.forceRefresh(rejectedAccessToken: nil) { [self] previous in
            try await performRefresh(previous)
        }
    }

    public func refreshAccessToken(rejected: String) async throws -> String? {
        do {
            return try await state.forceRefresh(rejectedAccessToken: rejected) { [self] previous in
                try await performRefresh(previous)
            }.accessToken
        } catch NemiAuthError.notSignedIn {
            return nil
        }
    }

    /// Revokes the refresh token (which ends the grant's session) and clears the store.
    /// Revocation is best effort: the local session is always cleared.
    public func signOut() async {
        let session = try? await state.session()
        await state.cancelRefreshAndClear()
        try? await tokenStore.clear()
        guard let session else { return }
        guard let document = try? await discovery(), let endpoint = Self.revocationEndpoint(for: document) else { return }
        let token = session.refreshToken ?? session.accessToken
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(nemiUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = FormEncoding.encode([
            ("token", token),
            ("token_type_hint", session.refreshToken == nil ? "access_token" : "refresh_token"),
            ("client_id", clientId),
        ])
        _ = try? await send(request)
    }

    /// The discovery document's `revocation_endpoint`, or `<origin>/api/oauth/revoke`
    /// (the documented location, next to the token endpoint) when it is not advertised.
    static func revocationEndpoint(for document: NemiDiscoveryDocument) -> URL? {
        if let endpoint = document.revocationEndpoint { return endpoint }
        guard var components = URLComponents(url: document.tokenEndpoint, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/api/oauth/revoke"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    // MARK: Token endpoint

    func performRefresh(_ previous: NemiSession) async throws -> NemiSession {
        guard let refreshToken = previous.refreshToken else { throw NemiAuthError.sessionExpired }
        let document = try await discovery()
        let response: TokenResponse
        do {
            response = try await tokenRequest(document: document, parameters: [
                ("grant_type", "refresh_token"),
                ("refresh_token", refreshToken),
                ("client_id", clientId),
            ])
        } catch NemiAuthError.tokenRequestFailed(_, let error, _) where error == "invalid_grant" {
            throw NemiAuthError.sessionExpired
        }
        return try await makeSession(from: response, previous: previous, nonce: nil, requireIDToken: false)
    }

    private func tokenRequest(document: NemiDiscoveryDocument, parameters: [(String, String)]) async throws -> TokenResponse {
        var request = URLRequest(url: document.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(nemiUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = FormEncoding.encode(parameters)
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            let body = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data)
            throw NemiAuthError.tokenRequestFailed(
                status: response.statusCode,
                error: body?.error ?? "http_\(response.statusCode)",
                description: body?.errorDescription
            )
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !token.accessToken.isEmpty else {
            throw NemiAuthError.invalidTokenResponse
        }
        return token
    }

    private func makeSession(from response: TokenResponse, previous: NemiSession?, nonce: String?, requireIDToken: Bool) async throws -> NemiSession {
        var user = previous?.user
        if let idToken = response.idToken {
            let keys = try await signingKeys(for: idToken)
            do {
                let claims = try IDTokenVerifier.verify(
                    idToken,
                    keys: keys,
                    issuer: issuerString,
                    clientId: clientId,
                    nonce: nonce,
                    accessToken: response.accessToken,
                    now: now()
                )
                // A refreshed id_token must be about the same person.
                if let previousSub = previous?.user?.sub, previousSub != claims.sub {
                    throw IDTokenValidationError.malformed
                }
                user = claims
            } catch let error as IDTokenValidationError {
                throw NemiAuthError.invalidIDToken(error)
            }
        } else if requireIDToken {
            throw NemiAuthError.invalidTokenResponse
        }
        let grantedScopes = response.scope.map { NemiScope.parse($0) } ?? previous?.scopes ?? []
        return NemiSession(
            accessToken: response.accessToken,
            // Refresh tokens rotate; keep the old one only if the server sent none.
            refreshToken: response.refreshToken ?? previous?.refreshToken,
            idToken: response.idToken ?? previous?.idToken,
            tokenType: response.tokenType ?? "Bearer",
            scopes: grantedScopes,
            expiresAt: now().addingTimeInterval(response.expiresIn ?? 3600),
            user: user
        )
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as URLError {
            throw NemiAuthError.network(error.localizedDescription)
        }
    }
}
