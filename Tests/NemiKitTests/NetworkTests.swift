import Foundation
import Testing
@testable import NemiKit

/// Everything that goes through `MockURLProtocol` lives under this one serialized suite.
@Suite("Network", .serialized)
struct NetworkTests {
    let fixture = TestIssuer()

    /// Serves discovery and JWKS, and passes anything else to `handler`.
    func serve(_ handler: @escaping @Sendable (URLRequest, Data) throws -> (Int, [String: String], Data)) {
        let discovery = json(fixture.discovery)
        let jwks = json(["keys": [fixture.jwk]])
        MockURLProtocol.reset { request, body in
            switch request.url?.path {
            case "/oauth/.well-known/openid-configuration": return (200, jsonHeaders, discovery)
            case "/oauth/jwks": return (200, jsonHeaders, jwks)
            default: return try handler(request, body)
            }
        }
    }

    func expiredSession(refreshToken: String = "nemi_ort_old") -> NemiSession {
        NemiSession(accessToken: "nemi_oat_old", refreshToken: refreshToken, idToken: nil,
                    scopes: [.openid, .offlineAccess, .filesRead], expiresAt: Date().addingTimeInterval(-10), user: nil)
    }

    func validSession(_ token: String = "nemi_oat_valid") -> NemiSession {
        NemiSession(accessToken: token, refreshToken: "nemi_ort_valid", idToken: nil,
                    scopes: [.openid, .offlineAccess], expiresAt: Date().addingTimeInterval(3600), user: nil)
    }

    // MARK: Token exchange

    @Test("authorization code exchange verifies the id_token and stores the session")
    func codeExchange() async throws {
        let store = InMemoryTokenStore()
        let auth = fixture.makeAuth(store: store)
        serve { _, _ in (404, [:], Data()) }
        let request = try await auth.makeAuthorizationRequest(scopes: [.profile, .offlineAccess])
        #expect(request.url.absoluteString.hasPrefix("https://nemi.test/oauth/authorize?"))

        let idToken = fixture.idToken(nonce: request.nonce, accessToken: "nemi_oat_1")
        serve { request, _ in
            #expect(request.url?.absoluteString == "https://nemi.test/api/oauth/token")
            return (200, jsonHeaders, json([
                "access_token": "nemi_oat_1", "token_type": "Bearer", "expires_in": 3600,
                "refresh_token": "nemi_ort_1", "scope": "openid profile offline_access", "id_token": idToken,
            ]))
        }
        let callback = URL(string: "com.example.app:/callback?code=code-1&state=\(request.state)&iss=https%3A%2F%2Fnemi.test%2Foauth")!
        let session = try await auth.completeAuthorization(callbackURL: callback, request: request)

        #expect(session.accessToken == "nemi_oat_1")
        #expect(session.refreshToken == "nemi_ort_1")
        #expect(session.scopes == [.openid, .profile, .offlineAccess])
        #expect(session.user?.sub == "pairwise-sub")
        #expect(session.expiresAt.timeIntervalSinceNow > 3500)
        #expect(try await store.load() == session)

        let tokenCall = try #require(MockURLProtocol.requests.first { $0.request.url?.path == "/api/oauth/token" })
        let form = FormEncoding.decode(tokenCall.body)
        #expect(form["grant_type"] == "authorization_code")
        #expect(form["code"] == "code-1")
        #expect(form["redirect_uri"] == "com.example.app:/callback")
        #expect(form["code_verifier"] == request.pkce.verifier)
        #expect(form["client_id"] == fixture.clientId)
        #expect(tokenCall.request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    }

    @Test("a token response with the wrong nonce is refused")
    func codeExchangeWrongNonce() async throws {
        let store = InMemoryTokenStore()
        let auth = fixture.makeAuth(store: store)
        serve { _, _ in (404, [:], Data()) }
        let request = try await auth.makeAuthorizationRequest()
        let idToken = fixture.idToken(nonce: "not-the-nonce")
        serve { _, _ in (200, jsonHeaders, json(["access_token": "nemi_oat_1", "expires_in": 3600, "id_token": idToken])) }
        let callback = URL(string: "com.example.app:/callback?code=c&state=\(request.state)&iss=https%3A%2F%2Fnemi.test%2Foauth")!
        await #expect(throws: NemiAuthError.invalidIDToken(.nonceMismatch)) {
            try await auth.completeAuthorization(callbackURL: callback, request: request)
        }
        #expect(try await store.load() == nil)
    }

    @Test("a discovery document for another issuer is refused")
    func discoveryIssuerMismatch() async throws {
        let auth = fixture.makeAuth(store: InMemoryTokenStore())
        var other = fixture.discovery
        other["issuer"] = "https://evil.test/oauth"
        let body = json(other)
        MockURLProtocol.reset { _, _ in (200, jsonHeaders, body) }
        await #expect(throws: NemiAuthError.issuerMismatch(expected: fixture.issuer, received: "https://evil.test/oauth")) {
            try await auth.discovery()
        }
    }

    @Test("token endpoint errors are surfaced")
    func tokenError() async throws {
        let auth = fixture.makeAuth(store: InMemoryTokenStore())
        serve { _, _ in (404, [:], Data()) }
        let request = try await auth.makeAuthorizationRequest()
        serve { _, _ in (400, jsonHeaders, json(["error": "invalid_grant", "error_description": "Code expired."])) }
        let callback = URL(string: "com.example.app:/callback?code=c&state=\(request.state)&iss=https%3A%2F%2Fnemi.test%2Foauth")!
        await #expect(throws: NemiAuthError.tokenRequestFailed(status: 400, error: "invalid_grant", description: "Code expired.")) {
            try await auth.completeAuthorization(callbackURL: callback, request: request)
        }
    }

    // MARK: Refresh

    @Test("an expired session refreshes and stores the rotated refresh token")
    func refreshRotates() async throws {
        let store = InMemoryTokenStore(session: expiredSession())
        let auth = fixture.makeAuth(store: store)
        serve { request, body in
            let form = FormEncoding.decode(body)
            #expect(form["grant_type"] == "refresh_token")
            #expect(form["refresh_token"] == "nemi_ort_old")
            #expect(form["client_id"] == "nemi_app_test123")
            return (200, jsonHeaders, json(["access_token": "nemi_oat_new", "expires_in": 3600, "refresh_token": "nemi_ort_new", "token_type": "Bearer"]))
        }
        #expect(try await auth.accessToken() == "nemi_oat_new")
        let stored = try #require(try await store.load())
        #expect(stored.refreshToken == "nemi_ort_new")
        #expect(stored.scopes == [.openid, .offlineAccess, .filesRead])
        // Still valid: no second refresh.
        #expect(try await auth.accessToken() == "nemi_oat_new")
        #expect(MockURLProtocol.count(path: "/api/oauth/token") == 1)
    }

    @Test("concurrent callers share a single refresh")
    func singleFlight() async throws {
        let store = InMemoryTokenStore(session: expiredSession())
        let auth = fixture.makeAuth(store: store)
        serve { _, body in
            let form = FormEncoding.decode(body)
            // A reused refresh token would revoke the chain on the real server.
            #expect(form["refresh_token"] == "nemi_ort_old")
            return (200, jsonHeaders, json(["access_token": "nemi_oat_new", "expires_in": 3600, "refresh_token": "nemi_ort_new"]))
        }
        _ = try await auth.discovery() // keep the timing about the token endpoint
        MockURLProtocol.delay = 0.2

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<12 { group.addTask { try await auth.accessToken() } }
            var all: [String] = []
            for try await token in group { all.append(token) }
            return all
        }
        #expect(tokens.count == 12)
        #expect(Set(tokens) == ["nemi_oat_new"])
        #expect(MockURLProtocol.count(path: "/api/oauth/token") == 1)
        #expect(try await store.load()?.refreshToken == "nemi_ort_new")
    }

    @Test("invalid_grant on refresh clears the session")
    func refreshInvalidGrant() async throws {
        let store = InMemoryTokenStore(session: expiredSession())
        let auth = fixture.makeAuth(store: store)
        serve { _, _ in (400, jsonHeaders, json(["error": "invalid_grant"])) }
        await #expect(throws: NemiAuthError.sessionExpired) { try await auth.accessToken() }
        #expect(try await store.load() == nil)
        await #expect(throws: NemiAuthError.notSignedIn) { try await auth.accessToken() }
    }

    @Test("signOut revokes the refresh token and clears the store")
    func signOut() async throws {
        let store = InMemoryTokenStore(session: validSession())
        let auth = fixture.makeAuth(store: store)
        serve { _, _ in (200, [:], Data()) }
        await auth.signOut()
        let revoke = try #require(MockURLProtocol.requests.first { $0.request.url?.path == "/api/oauth/revoke" })
        let form = FormEncoding.decode(revoke.body)
        #expect(form["token"] == "nemi_ort_valid")
        #expect(form["token_type_hint"] == "refresh_token")
        #expect(form["client_id"] == fixture.clientId)
        #expect(try await store.load() == nil)
        #expect(try await auth.currentSession() == nil)
    }

    // MARK: API client

    func makeClient(_ provider: any NemiAccessTokenProvider, retries: Int = 2) -> NemiClient {
        NemiClient(
            tokenProvider: provider,
            baseURL: URL(string: "https://nemi.test/api/v1")!,
            urlSession: MockURLProtocol.session(),
            maxRateLimitRetries: retries,
            maxRetryAfter: 60,
            sleep: { _ in }
        )
    }

    @Test("me() sends the bearer token and decodes")
    func me() async throws {
        let client = makeClient(StaticAccessTokenProvider("nemi_oat_x"))
        MockURLProtocol.reset { request, _ in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer nemi_oat_x")
            #expect(request.url?.path == "/api/v1/me")
            return (200, jsonHeaders, json(["id": "sub_1", "name": "Ada", "email_verified": true]))
        }
        let me = try await client.me()
        #expect(me.id == "sub_1")
        #expect(me.emailVerified == true)
    }

    @Test("a 401 refreshes once and retries")
    func unauthorizedRefreshes() async throws {
        let store = InMemoryTokenStore(session: validSession("nemi_oat_revoked"))
        let auth = fixture.makeAuth(store: store)
        let client = makeClient(auth)
        serve { request, _ in
            switch request.url?.path {
            case "/api/oauth/token":
                return (200, jsonHeaders, json(["access_token": "nemi_oat_fresh", "expires_in": 3600, "refresh_token": "nemi_ort_fresh"]))
            default:
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer nemi_oat_fresh" {
                    return (200, jsonHeaders, json(["workspaces": [["id": "w1", "name": "Home", "role": "owner"]]]))
                }
                return (401, ["WWW-Authenticate": "Bearer error=\"invalid_token\""], json(["error": ["code": "invalid_token", "message": "Token revoked."]]))
            }
        }
        let workspaces = try await client.workspaces()
        #expect(workspaces.first?.id == "w1")
        #expect(MockURLProtocol.count(path: "/api/oauth/token") == 1)
        #expect(MockURLProtocol.count(path: "/api/v1/workspaces") == 2)
    }

    @Test("a 401 without a way to refresh becomes invalid_token")
    func unauthorizedStatic() async throws {
        let client = makeClient(StaticAccessTokenProvider("nemi_oat_x"))
        MockURLProtocol.reset { _, _ in (401, jsonHeaders, json(["error": ["code": "invalid_token", "message": "Expired."]])) }
        await #expect(throws: NemiAPIError(status: 401, code: .invalidToken, message: "Expired.")) { try await client.me() }
    }

    @Test("429 is retried twice honoring Retry-After, then surfaced")
    func rateLimitRetries() async throws {
        let waits = WaitLog()
        let client = NemiClient(
            tokenProvider: StaticAccessTokenProvider("t"), baseURL: URL(string: "https://nemi.test/api/v1")!,
            urlSession: MockURLProtocol.session(), maxRateLimitRetries: 2, maxRetryAfter: 60,
            sleep: { await waits.append($0) }
        )
        MockURLProtocol.reset { _, _ in
            (429, ["Retry-After": "3", "Content-Type": "application/json"], json(["error": ["code": "rate_limited", "message": "Slow down."]]))
        }
        await #expect(throws: NemiAPIError(status: 429, code: .rateLimited, message: "Slow down.", retryAfter: 3)) {
            try await client.me()
        }
        #expect(MockURLProtocol.count(path: "/api/v1/me") == 3)
        #expect(await waits.values == [3, 3])

        let counter = Counter()
        MockURLProtocol.reset { _, _ in
            if counter.next() == 1 { return (429, ["Retry-After": "0"], Data()) }
            return (200, jsonHeaders, json(["id": "sub"]))
        }
        #expect(try await client.me().id == "sub")
    }

    @Test("insufficient_scope carries the required scope")
    func insufficientScope() async throws {
        let client = makeClient(StaticAccessTokenProvider("t"))
        MockURLProtocol.reset { _, _ in
            (403, jsonHeaders, json(["error": ["code": "insufficient_scope", "message": "This call needs files.read.", "required_scope": "files.read"]]))
        }
        do {
            _ = try await client.files.list(workspaceId: "w1")
            Issue.record("expected an error")
        } catch let error as NemiAPIError {
            #expect(error.code == .insufficientScope)
            #expect(error.requiredScope == .filesRead)
        }
    }

    @Test("files.list builds the query")
    func filesQuery() async throws {
        let client = makeClient(StaticAccessTokenProvider("t"))
        MockURLProtocol.reset { request, _ in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(items.map(\.name) == ["folder_id", "limit", "workspace_id"])
            #expect(items.first { $0.name == "workspace_id" }?.value == "w 1")
            return (200, jsonHeaders, json(["folders": [], "files": []]))
        }
        let listing = try await client.files.list(workspaceId: "w 1", folderId: "f1", limit: 10)
        #expect(listing.files.isEmpty)
    }

    @Test("upload runs create, PUT without the token, complete")
    func upload() async throws {
        let client = makeClient(StaticAccessTokenProvider("nemi_oat_secret"))
        MockURLProtocol.reset { request, body in
            switch (request.httpMethod, request.url?.host, request.url?.path) {
            case ("POST", "nemi.test", "/api/v1/files/uploads"):
                let payload = try JSONSerialization.jsonObject(with: body) as! [String: Any]
                #expect(payload["workspace_id"] as? String == "w1")
                #expect(payload["folder_id"] as? String == "f1")
                #expect(payload["name"] as? String == "notes.txt")
                #expect(payload["size"] as? Int == 5)
                #expect(payload["type"] as? String == "text/plain")
                return (201, jsonHeaders, json([
                    "upload_id": "u1", "upload_url": "https://bucket.test/put?sig=abc", "method": "PUT",
                    "headers": ["Content-Type": "text/plain; charset=utf-8", "x-amz-meta-owner": "w1"],
                    "max_size": 52_428_800, "expires_at": "2026-10-14T10:00:00.000Z",
                ]))
            case ("PUT", "bucket.test", "/put"):
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                // The server's headers win over the guessed type.
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "text/plain; charset=utf-8")
                #expect(request.value(forHTTPHeaderField: "x-amz-meta-owner") == "w1")
                return (200, [:], Data())
            case ("POST", "nemi.test", "/api/v1/files/uploads/u1/complete"):
                return (201, jsonHeaders, json(["id": "x1", "name": "notes.txt", "size": 5, "type": "text/plain", "workspace_id": "w1", "folder_id": "f1", "created_at": "2026-10-14T09:30:00Z"]))
            default:
                Issue.record("unexpected \(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
                return (500, [:], Data())
            }
        }
        let file = try await client.files.upload(data: Data("hello".utf8), name: "notes.txt", workspaceId: "w1", folderId: "f1")
        #expect(file.id == "x1")
        #expect(MockURLProtocol.requests.map { $0.request.httpMethod ?? "" } == ["POST", "PUT", "POST"])
    }

    @Test("a file over the ticket's max_size is refused before the PUT")
    func uploadOverTicketLimit() async throws {
        let client = makeClient(StaticAccessTokenProvider("t"))
        MockURLProtocol.reset { _, _ in
            (201, jsonHeaders, json(["upload_id": "u1", "upload_url": "https://bucket.test/put", "method": "PUT", "headers": [:], "max_size": 3, "expires_at": "2026-10-14T10:00:00.000Z"]))
        }
        await #expect(throws: NemiAPIError.self) {
            try await client.files.upload(data: Data("hello".utf8), name: "a.txt", workspaceId: "w1")
        }
        #expect(MockURLProtocol.requests.count == 1)
    }

    @Test("files over 50 MB are refused before any request")
    func uploadTooLarge() async throws {
        let client = makeClient(StaticAccessTokenProvider("t"))
        MockURLProtocol.reset { _, _ in (500, [:], Data()) }
        await #expect(throws: NemiAPIError.self) {
            try await client.files.upload(data: Data(count: 50 * 1024 * 1024 + 1), name: "big.bin", workspaceId: "w1")
        }
        #expect(MockURLProtocol.requests.isEmpty)
    }

    @Test("file update can move to the top level with an explicit null")
    func fileMoveToRoot() async throws {
        let client = makeClient(StaticAccessTokenProvider("t"))
        MockURLProtocol.reset { request, body in
            #expect(request.httpMethod == "PATCH")
            #expect(String(data: body, encoding: .utf8) == #"{"folder_id":null,"name":"b.pdf"}"#)
            return (200, jsonHeaders, json(["id": "x1", "name": "b.pdf", "size": 1, "type": "application/pdf", "workspace_id": "w1", "folder_id": NSNull(), "created_at": "2026-10-14T09:30:00Z"]))
        }
        let file = try await client.files.update(id: "x1", name: "b.pdf", moveTo: .root)
        #expect(file.folderId == nil)
    }

    @Test("allPhotos pages through cursors")
    func photoPaging() async throws {
        let client = makeClient(StaticAccessTokenProvider("t"))
        @Sendable func photo(_ id: String) -> [String: Any] {
            ["id": id, "name": "\(id).jpg", "width": 1, "height": 1, "size": 1, "captured_at": "2026-08-01T12:00:00Z", "favorite": false, "thumbnail_url": "https://cdn.test/\(id)"]
        }
        MockURLProtocol.reset { request, _ in
            let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems?.first { $0.name == "cursor" }?.value
            switch cursor {
            case nil: return (200, jsonHeaders, json(["photos": [photo("p1"), photo("p2")], "next_cursor": "c2"]))
            case "c2": return (200, jsonHeaders, json(["photos": [photo("p3")], "next_cursor": NSNull()]))
            default: return (400, [:], Data())
            }
        }
        var ids: [String] = []
        for try await item in client.gallery.allPhotos(workspaceId: "w1", pageSize: 2) { ids.append(item.id) }
        #expect(ids == ["p1", "p2", "p3"])
        #expect(MockURLProtocol.count(path: "/api/v1/gallery/photos") == 2)
    }

    @Test("gallery upload sends multipart with file and workspace_id")
    func galleryUpload() async throws {
        let client = makeClient(StaticAccessTokenProvider("t"))
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        MockURLProtocol.reset { request, body in
            let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            #expect(contentType.hasPrefix("multipart/form-data; boundary="))
            let text = String(decoding: body, as: UTF8.self)
            #expect(text.contains("name=\"workspace_id\"\r\n\r\nw1\r\n"))
            #expect(text.contains("name=\"file\"; filename=\"beach.jpg\"\r\nContent-Type: image/jpeg"))
            #expect(text.contains("name=\"captured_at\"\r\n\r\n2026-08-01T12:00:00Z\r\n"))
            return (201, jsonHeaders, json(["id": "p9", "workspace_id": "w1", "name": "beach.jpg", "width": 1, "height": 1, "size": 6, "captured_at": "2026-08-01T12:00:00.000Z", "favorite": false, "color": NSNull(), "thumbnail_url": "https://cdn.test/p9"]))
        }
        let photo = try await client.gallery.upload(imageData: jpeg, fileName: "beach.jpg", workspaceId: "w1", capturedAt: NemiDateFormat.parse("2026-08-01T12:00:00Z"))
        #expect(photo.id == "p9")
    }

    @Test("setFavorite returns the updated photo")
    func favorite() async throws {
        let client = makeClient(StaticAccessTokenProvider("t"))
        MockURLProtocol.reset { request, body in
            #expect(request.httpMethod == "PATCH")
            #expect(String(data: body, encoding: .utf8) == #"{"favorite":true}"#)
            return (200, jsonHeaders, json(["id": "p1", "workspace_id": "w1", "name": "a.jpg", "width": 1, "height": 1, "size": 1, "captured_at": "2026-08-01T12:00:00.000Z", "favorite": true, "color": NSNull(), "thumbnail_url": "https://cdn.test/t", "url": "https://cdn.test/full", "albums": []]))
        }
        let photo = try await client.gallery.setFavorite(true, photoId: "p1")
        #expect(photo.favorite)
        #expect(photo.albums == [])
    }

    @Test("docs, sheets, forms, canvas, gallery, folders and calendar hit the documented paths")
    func otherNamespaces() async throws {
        let client = makeClient(StaticAccessTokenProvider("t"))
        MockURLProtocol.reset { request, body in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/api/v1/docs"): return (200, jsonHeaders, json(["docs": [["id": "d1", "title": "A"]]]))
            case ("POST", "/api/v1/docs"):
                #expect(String(data: body, encoding: .utf8) == ##"{"markdown":"# Hi","title":"New","workspace_id":"w1"}"##)
                return (201, jsonHeaders, json(["id": "d2", "title": "New", "markdown": "# Hi"]))
            case ("PATCH", "/api/v1/sheets/s1/cells"):
                #expect(String(data: body, encoding: .utf8) == #"{"cells":{"A1":"x","B1":2}}"#)
                return (200, jsonHeaders, json(["id": "s1", "updated": 2]))
            case ("GET", "/api/v1/calendar/calendars"):
                return (200, jsonHeaders, json(["calendars": [["id": "cal1", "name": "Personal", "color": "#3366ff", "timezone": "Europe/Amsterdam", "primary": true]]]))
            case ("GET", "/api/v1/calendar/events"):
                #expect(request.url?.query?.contains("start=2026-10-01T00%3A00%3A00Z") == true)
                #expect(request.url?.query?.contains("calendar_id=cal1") == true)
                return (200, jsonHeaders, json(["events": []]))
            case ("POST", "/api/v1/calendar/events"):
                // No calendar_id: the server picks the primary calendar.
                #expect(String(data: body, encoding: .utf8) == #"{"end":"2026-10-01T01:00:00Z","start":"2026-10-01T00:00:00Z","title":"Focus"}"#)
                return (201, jsonHeaders, json(["id": "e1", "calendar_id": "cal1", "title": "Focus", "start": "2026-10-01T00:00:00.000Z", "end": "2026-10-01T01:00:00.000Z", "all_day": false, "location": NSNull(), "description": NSNull(), "timezone": NSNull(), "rrule": NSNull()]))
            case ("GET", "/api/v1/forms/f1/responses"):
                #expect(request.url?.query == "limit=10&offset=20")
                return (200, jsonHeaders, json(["form_id": "f1", "total": 21, "responses": [["Name": "Ada"]]]))
            case ("POST", "/api/v1/forms"):
                #expect(String(data: body, encoding: .utf8) == #"{"fields":[{"label":"Name","type":"short_text"}],"title":"RSVP"}"#)
                return (201, jsonHeaders, json(["form_id": "f9", "title": "RSVP", "fields": [["id": "q1", "label": "Name", "type": "short_text"]]]))
            case ("POST", "/api/v1/canvas"):
                #expect(String(data: body, encoding: .utf8) == #"{"title":"Plan","workspace_id":"w1"}"#)
                return (201, jsonHeaders, json(["id": "c2", "title": "Plan", "workspace_id": "w1", "updated_at": "2026-10-14T09:30:00.000Z"]))
            case ("PATCH", "/api/v1/canvas/c2"):
                #expect(String(data: body, encoding: .utf8) == #"{"elements":[{"text":"Hi","type":"text"}]}"#)
                return (200, jsonHeaders, json(["canvas_id": "c2", "title": "Plan", "element_count": 1, "elements": [["id": "e1", "type": "text", "text": "Hi"]]]))
            case ("DELETE", "/api/v1/canvas/c2"): return (204, [:], Data())
            case ("GET", "/api/v1/canvas/c1"):
                #expect(request.url?.query == "strokes=true")
                return (200, jsonHeaders, json(["canvas_id": "c1", "title": "Plan", "element_count": 0, "elements": []]))
            case ("POST", "/api/v1/gallery/albums/a1/photos"):
                #expect(String(data: body, encoding: .utf8) == #"{"photo_ids":["p1","p2"]}"#)
                return (200, jsonHeaders, json(["album_id": "a1", "added": 1, "skipped": 1]))
            case ("POST", "/api/v1/folders"):
                #expect(String(data: body, encoding: .utf8) == #"{"name":"2026","parent_id":"f1","workspace_id":"w1"}"#)
                return (201, jsonHeaders, json(["id": "f2", "name": "2026", "workspace_id": "w1", "parent_id": "f1"]))
            case ("DELETE", "/api/v1/docs/d1"), ("DELETE", "/api/v1/calendar/events/e1"): return (204, [:], Data())
            case ("DELETE", "/api/v1/forms/f1"): return (204, [:], Data())
            default:
                Issue.record("unexpected \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                return (500, [:], Data())
            }
        }
        #expect(try await client.docs.list().map(\.id) == ["d1"])
        #expect(try await client.sheets.updateCells(id: "s1", cells: ["A1": "x", "B1": 2]).updated == 2)
        #expect(try await client.docs.create(title: "New", markdown: "# Hi", workspaceId: "w1").id == "d2")
        let start = NemiDateFormat.parse("2026-10-01T00:00:00Z")!
        #expect(try await client.calendar.calendars().first?.primary == true)
        #expect(try await client.calendar.events(start: start, end: start.addingTimeInterval(86_400), calendarId: "cal1").isEmpty)
        #expect(try await client.calendar.create(title: "Focus", start: start, end: start.addingTimeInterval(3600)).calendarId == "cal1")
        try await client.calendar.delete(id: "e1")
        let responses = try await client.forms.responses(formId: "f1", limit: 10, offset: 20)
        #expect(responses.total == 21)
        #expect(responses.responses.first?["Name"] == "Ada")
        #expect(try await client.canvas.get(id: "c1", includeStrokes: true).id == "c1")
        let form = try await client.forms.create(title: "RSVP", fields: [["type": "short_text", "label": "Name"]])
        #expect(form.id == "f9")
        #expect(form.fields?.count == 1)
        let board = try await client.canvas.create(workspaceId: "w1", title: "Plan")
        #expect(board.id == "c2")
        #expect(board.workspaceId == "w1")
        let updated = try await client.canvas.update(id: "c2", elements: [["type": "text", "text": "Hi"]])
        #expect(updated.elementCount == 1)
        #expect(updated.elements?.first?["text"] == "Hi")
        try await client.canvas.delete(id: "c2")
        #expect(try await client.gallery.addPhotos(["p1", "p2"], toAlbum: "a1").skipped == 1)
        #expect(try await client.folders.create(name: "2026", workspaceId: "w1", parentId: "f1").parentId == "f1")
        try await client.docs.delete(id: "d1")
        try await client.forms.delete(id: "f1")
    }
}

actor WaitLog {
    var values: [TimeInterval] = []
    func append(_ value: TimeInterval) { values.append(value) }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
