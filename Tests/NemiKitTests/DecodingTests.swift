import Foundation
import Testing
@testable import NemiKit

@Suite("Model decoding")
struct DecodingTests {
    func decode<T: Decodable>(_ type: T.Type, _ string: String, listKeys: [String] = []) throws -> T {
        let decoder = NemiJSON.makeDecoder()
        decoder.userInfo[FlexibleList<NemiFile>.keysUserInfoKey] = listKeys
        return try decoder.decode(T.self, from: Data(string.utf8))
    }

    @Test func user() throws {
        let user = try decode(NemiUser.self, #"{"id":"sub_1","name":"Ada","username":"ada","picture":"https://cdn.test/a.png","email":"ada@example.com","email_verified":true}"#)
        #expect(user.id == "sub_1")
        #expect(user.emailVerified == true)
        #expect(user.picture?.host == "cdn.test")
        let minimal = try decode(NemiUser.self, #"{"id":"sub_2"}"#)
        #expect(minimal.name == nil)
    }

    @Test func workspaces() throws {
        let list = try decode(WorkspaceList.self, #"{"workspaces":[{"id":"w1","name":"Home","role":"owner"}]}"#)
        #expect(list.workspaces == [NemiWorkspace(id: "w1", name: "Home", role: "owner")])
    }

    @Test func fileListing() throws {
        let listing = try decode(NemiFileListing.self, """
        {"folders":[{"id":"f1","name":"Invoices"}],
         "files":[{"id":"x1","name":"a.pdf","size":1234,"type":"application/pdf","workspace_id":"w1","folder_id":null,"created_at":"2026-10-14T09:30:00.123Z"}]}
        """)
        #expect(listing.folders.first?.name == "Invoices")
        let file = try #require(listing.files.first)
        #expect(file.workspaceId == "w1")
        #expect(file.folderId == nil)
        #expect(file.size == 1234)
        #expect(abs(file.createdAt.timeIntervalSince1970 - 1_791_970_200.123) < 0.01)
    }

    @Test func downloadAndUploadTicket() throws {
        let link = try decode(NemiDownloadLink.self, #"{"url":"https://s3.test/x?sig=1","expires_at":"2026-10-14T09:45:00Z"}"#)
        #expect(link.url.host == "s3.test")
        let ticket = try decode(NemiUploadTicket.self, #"{"upload_id":"u1","upload_url":"https://s3.test/put","method":"PUT","expires_at":"2026-10-14T09:45:00Z"}"#)
        #expect(ticket.uploadId == "u1")
        #expect(ticket.uploadUrl.absoluteString == "https://s3.test/put")
    }

    @Test func photoPage() throws {
        let page = try decode(NemiPhotoPage.self, """
        {"photos":[{"id":"p1","name":"IMG_1.HEIC","width":4032,"height":3024,"size":2048000,"captured_at":"2026-08-01T12:00:00Z","favorite":true,"thumbnail_url":"https://cdn.test/t1"},
                   {"id":"p2","name":null,"width":10,"height":10,"size":1,"captured_at":null,"favorite":false,"thumbnail_url":"https://cdn.test/t2","url":"https://cdn.test/full2"}],
         "next_cursor":"c2"}
        """)
        #expect(page.photos.count == 2)
        #expect(page.photos[0].favorite)
        #expect(page.photos[0].thumbnailUrl?.absoluteString == "https://cdn.test/t1")
        #expect(page.photos[0].url == nil)
        #expect(page.photos[1].capturedAt == nil)
        #expect(page.photos[1].url?.absoluteString == "https://cdn.test/full2")
        #expect(page.nextCursor == "c2")
        let last = try decode(NemiPhotoPage.self, #"{"photos":[],"next_cursor":null}"#)
        #expect(last.nextCursor == nil)
    }

    @Test func albums() throws {
        let list = try decode(AlbumList.self, #"{"albums":[{"id":"a1","name":"Summer","count":12},{"id":"a2","name":"New"}]}"#)
        #expect(list.albums.map(\.count) == [12, 0])
    }

    @Test func documentAndSheet() throws {
        let doc = try decode(NemiDocument.self, ##"{"id":"d1","title":"Notes","markdown":"# Hi","workspace_id":"w1","updated_at":"2026-10-14T09:30:00Z"}"##)
        #expect(doc.markdown == "# Hi")
        let docs = try decode(FlexibleList<NemiDocument>.self, #"{"docs":[{"id":"d1","title":"Notes"}]}"#, listKeys: ["docs"])
        #expect(docs.items.first?.markdown == nil)

        let sheet = try decode(NemiSheet.self, #"{"id":"s1","title":"Budget","cells":{"A1":"Rent","B1":950.5,"C1":true,"D1":null}}"#)
        #expect(sheet.cells?["A1"] == "Rent")
        #expect(sheet.cells?["B1"] == .number(950.5))
        #expect(sheet.cells?["C1"] == .bool(true))
        #expect(sheet.cells?["D1"] == .null)
    }

    @Test("forms keep user keys verbatim in raw and answers")
    func forms() throws {
        let form = try decode(NemiForm.self, #"{"id":"f1","title":"RSVP","workspace_id":"w1","fields":[{"id":"q_1","type":"text"}],"extra_thing":1}"#)
        #expect(form.title == "RSVP")
        #expect(form.fields?.first?["id"] == "q_1")
        #expect(form.raw["extra_thing"] == .number(1))
        #expect(form.raw["workspace_id"] == "w1")

        let responses = try decode(FlexibleList<NemiFormResponse>.self, #"{"responses":[{"id":"r1","submitted_at":"2026-10-14T09:30:00Z","answers":{"q_1":"Yes"}}]}"#, listKeys: ["responses"])
        #expect(responses.items.first?.answers?["q_1"] == "Yes")
        #expect(responses.items.first?.submittedAt != nil)
    }

    @Test func canvas() throws {
        let boards = try decode(FlexibleList<NemiCanvas>.self, #"[{"id":"c1","name":"Plan"}]"#)
        #expect(boards.items.first?.title == "Plan")
        let other = try decode(FlexibleList<NemiCanvas>.self, #"{"whatever":[{"id":"c2","title":"Board"}],"total":1}"#, listKeys: ["canvases"])
        #expect(other.items.first?.id == "c2")
    }

    @Test func calendarEvents() throws {
        let list = try decode(FlexibleList<NemiCalendarEvent>.self, """
        {"events":[{"id":"e1","title":"Standup","start":"2026-10-14T09:00:00Z","end":"2026-10-14T09:15:00Z","all_day":false,"location":"Zoom"},
                   {"id":"e2","title":"Holiday","start":"2026-10-20","end":"2026-10-21","all_day":true}]}
        """, listKeys: ["events"])
        #expect(list.items.count == 2)
        #expect(list.items[0].location == "Zoom")
        #expect(list.items[1].allDay == true)
        #expect(NemiDateFormat.dateOnlyString(from: list.items[1].start) == "2026-10-20")
    }

    @Test("event drafts encode snake_case and date-only for all-day")
    func eventDraftEncoding() throws {
        let start = NemiDateFormat.parse("2026-10-20T00:00:00Z")!
        let allDay = NemiCalendarEventDraft(title: "Holiday", start: start, end: start.addingTimeInterval(86_400), allDay: true)
        let body = String(data: try NemiJSON.makeEncoder().encode(allDay), encoding: .utf8)!
        #expect(body == #"{"all_day":true,"end":"2026-10-21","start":"2026-10-20","title":"Holiday"}"#)
        let timed = NemiCalendarEventDraft(start: start)
        #expect(String(data: try NemiJSON.makeEncoder().encode(timed), encoding: .utf8)! == #"{"start":"2026-10-20T00:00:00Z"}"#)
    }

    @Test("cell keys are not rewritten when encoding")
    func cellKeys() throws {
        let body = try NemiJSON.makeEncoder().encode(["cells": ["A1": JSONValue.string("x"), "B_2": 1]])
        #expect(String(data: body, encoding: .utf8) == #"{"cells":{"A1":"x","B_2":1}}"#)
    }

    @Test("id_token claims round-trip through the token store encoding")
    func sessionRoundTrip() throws {
        let fixture = TestIssuer()
        let claims = try IDTokenVerifier.verify(fixture.idToken(nonce: "n"), keys: [fixture.nemiJWK], issuer: fixture.issuer, clientId: fixture.clientId, nonce: "n")
        let session = NemiSession(accessToken: "a", refreshToken: "r", idToken: "i", scopes: [.openid], expiresAt: Date(timeIntervalSince1970: 1_800_000_000), user: claims)
        let decoded = try JSONDecoder().decode(NemiSession.self, from: JSONEncoder().encode(session))
        #expect(decoded == session)
    }
}

@Suite("Error mapping")
struct ErrorMappingTests {
    func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://nemi.test/api/v1/files")!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    @Test func insufficientScope() {
        let body = Data(#"{"error":{"code":"insufficient_scope","message":"This call needs files.read.","required_scope":"files.read"}}"#.utf8)
        let error = NemiAPIError.from(data: body, response: response(403))
        #expect(error.status == 403)
        #expect(error.code == .insufficientScope)
        #expect(error.message == "This call needs files.read.")
        #expect(error.requiredScope == .filesRead)
    }

    @Test func rateLimited() {
        let body = Data(#"{"error":{"code":"rate_limited","message":"Slow down."}}"#.utf8)
        let error = NemiAPIError.from(data: body, response: response(429, ["Retry-After": "7"]))
        #expect(error.code == .rateLimited)
        #expect(error.retryAfter == 7)
    }

    @Test("status fallback when the body is not JSON")
    func statusFallback() {
        for (status, code) in [(400, NemiAPIError.Code.invalidRequest), (401, .invalidToken), (403, .forbidden), (404, .notFound),
                               (409, .conflict), (413, .tooLarge), (429, .rateLimited), (500, .serverError), (503, .serverError)] {
            let error = NemiAPIError.from(data: Data("<html>oops</html>".utf8), response: response(status))
            #expect(error.code == code)
            #expect(error.message == "<html>oops</html>")
        }
    }

    @Test func retryAfterDate() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let value = formatter.string(from: Date().addingTimeInterval(30))
        let seconds = NemiAPIError.parseRetryAfter(value)
        #expect(seconds != nil && seconds! > 25 && seconds! <= 30)
    }

    @Test func formEncoding() {
        let body = String(data: FormEncoding.encode([("a", "x+y z"), ("redirect_uri", "com.example.app:/callback")]), encoding: .utf8)
        #expect(body == "a=x%2By%20z&redirect_uri=com.example.app%3A%2Fcallback")
    }
}
