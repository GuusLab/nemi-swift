import Foundation

/// The Nemi REST API (`https://nemilab.com/api/v1`).
///
/// ```swift
/// let client = NemiClient(auth: auth)
/// let me = try await client.me()
/// let listing = try await client.files.list(workspaceId: workspace.id)
/// ```
///
/// Access tokens come from the provider (usually `NemiAuth`) and are refreshed
/// automatically; a 401 triggers one refresh and one retry. A 429 is retried up
/// to `maxRateLimitRetries` times, waiting for `Retry-After`.
public actor NemiClient {
    public nonisolated let baseURL: URL
    public nonisolated let tokenProvider: any NemiAccessTokenProvider
    /// How often a 429 is retried. Defaults to 2.
    public nonisolated let maxRateLimitRetries: Int
    /// The longest `Retry-After` the client waits for before giving up.
    public nonisolated let maxRetryAfter: TimeInterval

    let transport: HTTPTransport
    let sleep: @Sendable (TimeInterval) async throws -> Void

    /// Uses `auth` for tokens, refreshing as needed.
    public init(auth: NemiAuth, baseURL: URL = NemiKit.defaultAPIBaseURL, urlSession: URLSession = .shared) {
        self.init(tokenProvider: auth, baseURL: baseURL, urlSession: urlSession)
    }

    /// Uses a fixed access token.
    public init(accessToken: String, baseURL: URL = NemiKit.defaultAPIBaseURL, urlSession: URLSession = .shared) {
        self.init(tokenProvider: StaticAccessTokenProvider(accessToken), baseURL: baseURL, urlSession: urlSession)
    }

    public init(
        tokenProvider: any NemiAccessTokenProvider,
        baseURL: URL = NemiKit.defaultAPIBaseURL,
        urlSession: URLSession = .shared,
        maxRateLimitRetries: Int = 2,
        maxRetryAfter: TimeInterval = 60
    ) {
        self.init(
            tokenProvider: tokenProvider,
            baseURL: baseURL,
            urlSession: urlSession,
            maxRateLimitRetries: maxRateLimitRetries,
            maxRetryAfter: maxRetryAfter,
            sleep: { seconds in try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }
        )
    }

    init(
        tokenProvider: any NemiAccessTokenProvider,
        baseURL: URL,
        urlSession: URLSession,
        maxRateLimitRetries: Int,
        maxRetryAfter: TimeInterval,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void
    ) {
        self.tokenProvider = tokenProvider
        self.baseURL = baseURL
        self.transport = HTTPTransport(session: urlSession)
        self.maxRateLimitRetries = maxRateLimitRetries
        self.maxRetryAfter = maxRetryAfter
        self.sleep = sleep
    }

    // MARK: Namespaces

    public nonisolated var files: Files { Files(client: self) }
    public nonisolated var folders: Folders { Folders(client: self) }
    public nonisolated var gallery: Gallery { Gallery(client: self) }
    public nonisolated var docs: Docs { Docs(client: self) }
    public nonisolated var sheets: Sheets { Sheets(client: self) }
    public nonisolated var forms: Forms { Forms(client: self) }
    public nonisolated var canvas: Canvas { Canvas(client: self) }
    public nonisolated var calendar: Calendar { Calendar(client: self) }

    // MARK: Account

    /// `GET /me`.
    public func me() async throws -> NemiUser {
        try await get("me")
    }

    /// `GET /workspaces`.
    public func workspaces() async throws -> [NemiWorkspace] {
        let list: WorkspaceList = try await get("workspaces")
        return list.workspaces
    }

    // MARK: Plumbing

    enum Body: Sendable {
        case none
        case json(Data)
        case multipart(Data, boundary: String)
    }

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:], listKeys: [String] = []) async throws -> T {
        let data = try await perform("GET", path, query: query, body: .none)
        return try decode(T.self, from: data, listKeys: listKeys)
    }

    func send<T: Decodable>(_ method: String, _ path: String, json: some Encodable) async throws -> T {
        let body = try NemiJSON.makeEncoder().encode(json)
        let data = try await perform(method, path, query: [:], body: .json(body))
        return try decode(T.self, from: data)
    }

    func sendDiscarding(_ method: String, _ path: String, json: (some Encodable)?) async throws {
        let body: Body = try json.map { .json(try NemiJSON.makeEncoder().encode($0)) } ?? .none
        _ = try await perform(method, path, query: [:], body: body)
    }

    func list<T: Decodable>(_ path: String, query: [String: String?] = [:], keys: [String]) async throws -> [T] {
        let list: FlexibleList<T> = try await get(path, query: query, listKeys: keys)
        return list.items
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data, listKeys: [String] = []) throws -> T {
        let decoder = NemiJSON.makeDecoder()
        decoder.userInfo[FlexibleList<NemiFile>.keysUserInfoKey] = listKeys
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NemiAPIError(status: 200, code: "invalid_response", message: "The response could not be read: \(error)")
        }
    }

    /// Runs one API call with auth, a single refresh on 401 and rate limit retries.
    @discardableResult
    func perform(_ method: String, _ path: String, query: [String: String?], body: Body) async throws -> Data {
        var token = try await tokenProvider.accessToken()
        var refreshed = false
        var rateLimitRetries = 0

        while true {
            let request = try makeRequest(method, path, query: query, body: body, token: token)
            let (data, response) = try await transport.send(request)
            if (200..<300).contains(response.statusCode) { return data }

            let error = NemiAPIError.from(data: data, response: response)
            if response.statusCode == 401, !refreshed,
               let fresh = try await tokenProvider.refreshAccessToken(rejected: token) {
                token = fresh
                refreshed = true
                continue
            }
            if response.statusCode == 429, rateLimitRetries < maxRateLimitRetries {
                let wait = error.retryAfter ?? Double(1 << rateLimitRetries)
                if wait <= maxRetryAfter {
                    rateLimitRetries += 1
                    try await sleep(wait)
                    continue
                }
            }
            throw error
        }
    }

    func makeRequest(_ method: String, _ path: String, query: [String: String?], body: Body, token: String) throws -> URLRequest {
        var url = baseURL.appendingAPIPath(path)
        let items = query.compactMap { key, value in value.map { (key, $0) } }.sorted { $0.0 < $1.0 }
        if !items.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.percentEncodedQuery = items
                .map { "\(FormEncoding.escape($0.0))=\(FormEncoding.escape($0.1))" }
                .joined(separator: "&")
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(nemiUserAgent, forHTTPHeaderField: "User-Agent")
        switch body {
        case .none:
            break
        case .json(let data):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        case .multipart(let data, let boundary):
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        }
        return request
    }
}
