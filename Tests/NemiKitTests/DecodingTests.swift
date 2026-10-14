import Foundation
import Testing
@testable import NemiKit

/// Fixtures are shaped like the v1 routes' answers (app/api/v1 and lib/developer).
@Suite("Model decoding")
struct DecodingTests {
    func decode<T: Decodable>(_ type: T.Type, _ string: String) throws -> T {
        try NemiJSON.makeDecoder().decode(T.self, from: Data(string.utf8))
    }

    @Test("me reads preferred_username as username")
    func user() throws {
        let user = try decode(NemiUser.self, #"{"id":"sub_1","name":"Ada","preferred_username":"ada","picture":"https://cdn.test/a.png","email":"ada@example.com","email_verified":true}"#)
        #expect(user.id == "sub_1")
        #expect(user.username == "ada")
        #expect(user.emailVerified == true)
        #expect(user.picture?.host == "cdn.test")
        let minimal = try decode(NemiUser.self, #"{"id":"sub_2","name":null,"picture":null}"#)
        #expect(minimal.name == nil)
        #expect(minimal.username == nil)
    }

    @Test func workspaces() throws {
        let list = try decode(WorkspaceList.self, #"{"workspaces":[{"id":"w1","name":"Home","role":"owner"}]}"#)
        #expect(list.workspaces == [NemiWorkspace(id: "w1", name: "Home", role: "owner")])
    }

    @Test func fileListing() throws {
        let listing = try decode(NemiFileListing.self, """
        {"folders":[{"id":"f1","name":"Invoices"}],
         "files":[{"id":"x1","name":"a.pdf","size":1234,"type":"application/pdf","workspace_id":"w1","folder_id":null,"created_at":"2026-10-14T09:30:00.123Z"},
                  {"id":"x2","name":"b","size":0,"type":null,"workspace_id":null,"folder_id":null,"created_at":null}]}
        """)
        #expect(listing.folders.first?.name == "Invoices")
        #expect(listing.folders.first?.parentId == nil)
        let file = try #require(listing.files.first)
        #expect(file.workspaceId == "w1")
        #expect(file.folderId == nil)
        #expect(file.size == 1234)
        #expect(abs((file.createdAt?.timeIntervalSince1970 ?? 0) - 1_791_970_200.123) < 0.01)
        #expect(listing.files[1].type == nil)
        #expect(listing.files[1].createdAt == nil)
    }

    @Test func folderCreate() throws {
        let folder = try decode(NemiFolder.self, #"{"id":"f2","name":"2026","workspace_id":"w1","parent_id":"f1"}"#)
        #expect(folder.workspaceId == "w1")
        #expect(folder.parentId == "f1")
    }

    @Test("upload tickets carry headers verbatim and max_size")
    func downloadAndUploadTicket() throws {
        let link = try decode(NemiDownloadLink.self, #"{"url":"https://s3.test/x?sig=1","expires_at":"2026-10-14T09:45:00Z"}"#)
        #expect(link.url.host == "s3.test")
        let ticket = try decode(NemiUploadTicket.self, """
        {"upload_id":"u1","upload_url":"https://s3.test/put","method":"PUT",
         "headers":{"Content-Type":"text/plain","x-amz-meta-file_id":"abc"},"max_size":52428800,"expires_at":"2026-10-14T09:45:00.000Z"}
        """)
        #expect(ticket.uploadId == "u1")
        #expect(ticket.uploadUrl.absoluteString == "https://s3.test/put")
        #expect(ticket.headers == ["Content-Type": "text/plain", "x-amz-meta-file_id": "abc"])
        #expect(ticket.maxSize == 52_428_800)
    }

    @Test func photoPage() throws {
        let page = try decode(NemiPhotoPage.self, """
        {"photos":[{"id":"p1","workspace_id":"w1","name":"IMG_1.HEIC","width":4032,"height":3024,"size":2048000,"captured_at":"2026-08-01T12:00:00.000Z","favorite":true,"color":"#aabbcc","thumbnail_url":"https://cdn.test/t1"},
                   {"id":"p2","workspace_id":"w1","name":"x.jpg","width":10,"height":10,"size":1,"captured_at":"2026-08-01T12:00:00.000Z","favorite":false,"color":null,"thumbnail_url":"https://cdn.test/t2"}],
         "next_cursor":"c2"}
        """)
        #expect(page.photos.count == 2)
        #expect(page.photos[0].favorite)
        #expect(page.photos[0].workspaceId == "w1")
        #expect(page.photos[0].color == "#aabbcc")
        #expect(page.photos[0].thumbnailUrl?.absoluteString == "https://cdn.test/t1")
        #expect(page.photos[0].url == nil)
        #expect(page.photos[0].albums == nil)
        #expect(page.photos[1].color == nil)
        #expect(page.nextCursor == "c2")
        let last = try decode(NemiPhotoPage.self, #"{"photos":[],"next_cursor":null}"#)
        #expect(last.nextCursor == nil)
    }

    @Test("a single photo adds url and albums")
    func singlePhoto() throws {
        let photo = try decode(NemiPhoto.self, """
        {"id":"p1","workspace_id":"w1","name":"a.jpg","width":1,"height":1,"size":1,"captured_at":"2026-08-01T12:00:00.000Z","favorite":false,"color":null,
         "thumbnail_url":"https://cdn.test/t1","url":"https://cdn.test/full1","albums":[{"id":"a1","name":"Summer"}]}
        """)
        #expect(photo.url?.absoluteString == "https://cdn.test/full1")
        #expect(photo.albums == [NemiAlbumReference(id: "a1", name: "Summer")])
    }

    @Test func albums() throws {
        let list = try decode(AlbumList.self, #"{"albums":[{"id":"a1","name":"Summer","count":12,"cover_url":"https://cdn.test/c"},{"id":"a2","name":"New","count":0,"cover_url":null}]}"#)
        #expect(list.albums.map(\.count) == [12, 0])
        #expect(list.albums[0].coverUrl?.absoluteString == "https://cdn.test/c")
        #expect(list.albums[1].coverUrl == nil)
        let added = try decode(NemiAlbumAddResult.self, #"{"album_id":"a1","added":3,"skipped":1}"#)
        #expect(added == NemiAlbumAddResult(albumId: "a1", added: 3, skipped: 1))
    }

    @Test func docs() throws {
        let list = try decode(DocList.self, #"{"docs":[{"id":"d1","title":"Notes","preview":"Hello","workspace_id":"w1","updated_at":"2026-10-14T09:30:00.000Z"}]}"#)
        #expect(list.docs.first?.preview == "Hello")
        #expect(list.docs.first?.markdown == nil)
        let doc = try decode(NemiDocument.self, ##"{"id":"d1","title":"Notes","preview":null,"workspace_id":"w1","updated_at":null,"markdown":"# Hi"}"##)
        #expect(doc.markdown == "# Hi")
        #expect(doc.updatedAt == nil)
    }

    @Test func sheets() throws {
        let list = try decode(SheetList.self, #"{"sheets":[{"id":"s1","title":"Budget","workspace_id":"w1","updated_at":"2026-10-14T09:30:00.000Z"}]}"#)
        #expect(list.sheets.first?.cells == nil)
        let sheet = try decode(NemiSheet.self, """
        {"id":"s1","title":"Budget","workspace_id":"w1","updated_at":null,"rows":100,"cols":26,
         "cells":{"A1":{"value":"Rent","display":"Rent"},"B1":{"value":950.5,"display":"€950.50"},"C1":{"value":true,"display":"TRUE"},
                  "D1":{"value":"=SUM(B1:B2)","display":"1900"},"E1":{"value":7}}}
        """)
        #expect(sheet.rows == 100)
        #expect(sheet.cols == 26)
        #expect(sheet.cells?["A1"] == NemiSheetCell(value: "Rent", display: "Rent"))
        #expect(sheet.cells?["B1"]?.value == .number(950.5))
        #expect(sheet.cells?["B1"]?.text == "€950.50")
        #expect(sheet.cells?["C1"]?.value == .bool(true))
        #expect(sheet.cells?["D1"]?.value == "=SUM(B1:B2)")
        #expect(sheet.cells?["D1"]?.text == "1900")
        #expect(sheet.cells?["E1"]?.display == nil)
        #expect(sheet.cells?["E1"]?.text == "7")
        // A bare value is tolerated.
        let bare = try decode(NemiSheet.self, #"{"id":"s2","title":"T","cells":{"A1":"x"}}"#)
        #expect(bare.cells?["A1"] == NemiSheetCell(value: "x"))
        let update = try decode(NemiSheetCellsUpdate.self, #"{"id":"s1","updated":2}"#)
        #expect(update.updated == 2)
    }

    @Test("form summaries and the form_id detail shape both decode")
    func forms() throws {
        let list = try decode(FormList.self, #"{"forms":[{"id":"f1","title":"RSVP","published":true,"workspace_id":"w1","updated_at":"2026-10-14T09:30:00.000Z"}]}"#)
        #expect(list.forms.first?.published == true)
        let form = try decode(NemiForm.self, """
        {"form_id":"f1","title":"RSVP","description":"Come along","fields":[{"id":"q_1","type":"short_text","label":"Name"}],
         "response_count":4,"respond_url":"https://nemi.test/f/tok","created_at":1791970200000,"updated_at":1791970200000,"collect_name":true}
        """)
        #expect(form.id == "f1")
        #expect(form.description == "Come along")
        #expect(form.fields?.first?["id"] == "q_1")
        #expect(form.responseCount == 4)
        #expect(form.respondUrl?.path == "/f/tok")
        #expect(form.updatedAt?.timeIntervalSince1970 == 1_791_970_200)
        #expect(form.raw["collect_name"] == .bool(true))
    }

    @Test("form responses are header-keyed records, keys kept verbatim")
    func formResponses() throws {
        let page = try decode(NemiFormResponsePage.self, #"{"form_id":"f1","total":2,"responses":[{"Submitted at":"2026-10-14","Your_name":"Ada"},{"Submitted at":"2026-10-13","Your_name":"Grace"}]}"#)
        #expect(page.formId == "f1")
        #expect(page.total == 2)
        #expect(page.responses.first?["Your_name"] == "Ada")
        #expect(page.responses.last?["Submitted at"] == "2026-10-13")
    }

    @Test func canvas() throws {
        let list = try decode(CanvasList.self, #"{"canvases":[{"id":"c1","title":"Plan","workspace_id":"w1","updated_at":"2026-10-14T09:30:00.000Z"}]}"#)
        #expect(list.canvases.first?.title == "Plan")
        let board = try decode(NemiCanvas.self, #"{"canvas_id":"c1","title":"Plan","element_count":2,"elements":[{"type":"text"},{"type":"stroke","point_count":40}],"updated_at":"2026-10-14T09:30:00.000Z"}"#)
        #expect(board.id == "c1")
        #expect(board.elementCount == 2)
        #expect(board.elements?.last?["point_count"] == .number(40))
    }

    @Test func calendars() throws {
        let list = try decode(CalendarList.self, ##"{"calendars":[{"id":"cal1","name":"Personal","color":"#3366ff","timezone":"Europe/Amsterdam","primary":true}]}"##)
        #expect(list.calendars.first?.primary == true)
        #expect(list.calendars.first?.timezone == "Europe/Amsterdam")
    }

    @Test func calendarEvents() throws {
        let list = try decode(EventList.self, """
        {"events":[{"id":"e1","calendar_id":"cal1","title":"Standup","start":"2026-10-14T09:00:00.000Z","end":"2026-10-14T09:15:00.000Z","all_day":false,"location":"Zoom","description":null,"timezone":"Europe/Amsterdam","rrule":"FREQ=WEEKLY;BYDAY=MO"},
                   {"id":"e2","calendar_id":"cal1","title":"Holiday","start":"2026-10-20","end":"2026-10-21","all_day":true,"location":null,"description":null,"timezone":null,"rrule":null}]}
        """)
        #expect(list.events.count == 2)
        #expect(list.events[0].calendarId == "cal1")
        #expect(list.events[0].rrule == "FREQ=WEEKLY;BYDAY=MO")
        #expect(list.events[0].location == "Zoom")
        #expect(list.events[1].allDay)
        #expect(NemiDateFormat.dateOnlyString(from: list.events[1].start) == "2026-10-20")
    }

    @Test("event drafts encode snake_case and date-only for all-day")
    func eventDraftEncoding() throws {
        let start = NemiDateFormat.parse("2026-10-20T00:00:00Z")!
        let allDay = NemiCalendarEventDraft(calendarId: "cal1", title: "Holiday", start: start, end: start.addingTimeInterval(86_400), allDay: true)
        let body = String(data: try NemiJSON.makeEncoder().encode(allDay), encoding: .utf8)!
        #expect(body == #"{"all_day":true,"calendar_id":"cal1","end":"2026-10-21","start":"2026-10-20","title":"Holiday"}"#)
        let timed = NemiCalendarEventDraft(start: start, timezone: "Europe/Amsterdam", rrule: "FREQ=DAILY")
        #expect(String(data: try NemiJSON.makeEncoder().encode(timed), encoding: .utf8)! == #"{"rrule":"FREQ=DAILY","start":"2026-10-20T00:00:00Z","timezone":"Europe/Amsterdam"}"#)
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
