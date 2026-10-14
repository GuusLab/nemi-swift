import Foundation

// Without `workspaceId`, lists span every workspace the person can read and
// creates go to the first workspace they can write in.

extension NemiClient {
    /// Docs as Markdown. Needs `docs.read` / `docs.write`.
    public struct Docs: Sendable {
        let client: NemiClient

        /// `GET /docs`: summaries with `preview`, without `markdown`.
        public func list(workspaceId: String? = nil, limit: Int? = nil) async throws -> [NemiDocument] {
            let list: DocList = try await client.get("docs", query: ["workspace_id": workspaceId, "limit": limit.map(String.init)])
            return list.docs
        }

        /// `GET /docs/{id}`: includes `markdown`.
        public func get(id: String) async throws -> NemiDocument {
            try await client.get("docs/\(id)")
        }

        /// `POST /docs`.
        public func create(title: String, markdown: String? = nil, workspaceId: String? = nil) async throws -> NemiDocument {
            struct Create: Encodable {
                let workspaceId: String?
                let title: String
                let markdown: String?
                enum CodingKeys: String, CodingKey { case workspaceId = "workspace_id", title, markdown }
            }
            return try await client.send("POST", "docs", json: Create(workspaceId: workspaceId, title: title, markdown: markdown))
        }

        /// `PATCH /docs/{id}`. `mode: .append` adds `markdown` to the end instead of replacing the body.
        public func update(id: String, title: String? = nil, markdown: String? = nil, mode: NemiDocUpdateMode? = nil) async throws -> NemiDocument {
            struct Patch: Encodable { let title: String?; let markdown: String?; let mode: NemiDocUpdateMode? }
            return try await client.send("PATCH", "docs/\(id)", json: Patch(title: title, markdown: markdown, mode: markdown == nil ? nil : mode))
        }

        /// `DELETE /docs/{id}`. Final: documents have no trash.
        public func delete(id: String) async throws {
            try await client.delete("docs/\(id)")
        }
    }

    /// Sheets as cells. Needs `sheets.read` / `sheets.write`.
    public struct Sheets: Sendable {
        let client: NemiClient

        /// `GET /sheets`: summaries without cells.
        public func list(workspaceId: String? = nil, limit: Int? = nil) async throws -> [NemiSheet] {
            let list: SheetList = try await client.get("sheets", query: ["workspace_id": workspaceId, "limit": limit.map(String.init)])
            return list.sheets
        }

        /// `GET /sheets/{id}`: the first tab, with `rows`, `cols` and `cells` keyed by A1 references.
        public func get(id: String) async throws -> NemiSheet {
            try await client.get("sheets/\(id)")
        }

        /// `POST /sheets`, optionally with starting cells.
        public func create(title: String, cells: [String: JSONValue]? = nil, workspaceId: String? = nil) async throws -> NemiSheet {
            struct Create: Encodable {
                let workspaceId: String?
                let title: String
                let cells: [String: JSONValue]?
                enum CodingKeys: String, CodingKey { case workspaceId = "workspace_id", title, cells }
            }
            return try await client.send("POST", "sheets", json: Create(workspaceId: workspaceId, title: title, cells: cells))
        }

        /// `PATCH /sheets/{id}/cells`. Keys are A1 references. People editing live see it at once.
        ///
        /// ```swift
        /// try await client.sheets.updateCells(id: id, cells: ["A1": "Name", "B1": 42])
        /// ```
        @discardableResult
        public func updateCells(id: String, cells: [String: JSONValue]) async throws -> NemiSheetCellsUpdate {
            struct Patch: Encodable { let cells: [String: JSONValue] }
            return try await client.send("PATCH", "sheets/\(id)/cells", json: Patch(cells: cells))
        }

        /// `DELETE /sheets/{id}`.
        public func delete(id: String) async throws {
            try await client.delete("sheets/\(id)")
        }
    }

    /// Forms and their responses. Needs `forms.read` / `forms.write`.
    public struct Forms: Sendable {
        let client: NemiClient

        /// `GET /forms`: summaries (`id`, `title`, `published`, `workspaceId`, `updatedAt`).
        public func list(workspaceId: String? = nil, limit: Int? = nil) async throws -> [NemiForm] {
            let list: FormList = try await client.get("forms", query: ["workspace_id": workspaceId, "limit": limit.map(String.init)])
            return list.forms
        }

        /// `GET /forms/{id}`: the form with its questions.
        public func get(id: String) async throws -> NemiForm {
            try await client.get("forms/\(id)")
        }

        /// `GET /forms/{id}/responses`, newest first. Page with `offset`.
        public func responses(formId: String, limit: Int? = nil, offset: Int? = nil) async throws -> NemiFormResponsePage {
            try await client.get("forms/\(formId)/responses", query: [
                "limit": limit.map(String.init),
                "offset": offset.map(String.init),
            ])
        }

        /// `POST /forms`. `fields` are the questions, as in the Nemi docs, passed through as JSON.
        public func create(title: String, description: String? = nil, fields: [JSONValue]? = nil, workspaceId: String? = nil) async throws -> NemiForm {
            struct Create: Encodable {
                let workspaceId: String?
                let title: String
                let description: String?
                let fields: [JSONValue]?
                enum CodingKeys: String, CodingKey { case workspaceId = "workspace_id", title, description, fields }
            }
            return try await client.send("POST", "forms", json: Create(workspaceId: workspaceId, title: title, description: description, fields: fields))
        }

        /// `DELETE /forms/{id}`.
        public func delete(id: String) async throws {
            try await client.delete("forms/\(id)")
        }
    }

    /// Canvas boards. Needs `canvas.read` / `canvas.write`.
    public struct Canvas: Sendable {
        let client: NemiClient

        /// `GET /canvas`: summaries.
        public func list(workspaceId: String? = nil, limit: Int? = nil) async throws -> [NemiCanvas] {
            let list: CanvasList = try await client.get("canvas", query: ["workspace_id": workspaceId, "limit": limit.map(String.init)])
            return list.canvases
        }

        /// `GET /canvas/{id}`: the board's shapes and text; pen strokes only with `includeStrokes`.
        public func get(id: String, includeStrokes: Bool = false) async throws -> NemiCanvas {
            try await client.get("canvas/\(id)", query: ["strokes": includeStrokes ? "true" : nil])
        }

        /// `POST /canvas`: an empty board. Returns the summary.
        public func create(workspaceId: String? = nil, title: String? = nil) async throws -> NemiCanvas {
            struct Create: Encodable {
                let workspaceId: String?
                let title: String?
                enum CodingKeys: String, CodingKey { case workspaceId = "workspace_id", title }
            }
            return try await client.send("POST", "canvas", json: Create(workspaceId: workspaceId, title: title))
        }

        /// `PATCH /canvas/{id}`. `elements` REPLACES the whole board: get it,
        /// change the list, send it all back. Returns the board.
        public func update(id: String, title: String? = nil, elements: [JSONValue]? = nil) async throws -> NemiCanvas {
            guard title != nil || elements != nil else {
                throw NemiAPIError(status: 400, code: .invalidRequest, message: "Send title, elements or both.")
            }
            struct Patch: Encodable { let title: String?; let elements: [JSONValue]? }
            return try await client.send("PATCH", "canvas/\(id)", json: Patch(title: title, elements: elements))
        }

        /// `DELETE /canvas/{id}`. Final.
        public func delete(id: String) async throws {
            try await client.delete("canvas/\(id)")
        }
    }

    /// Calendars made in Nemi. Needs `calendar.read` / `calendar.write`.
    public struct Calendar: Sendable {
        let client: NemiClient

        /// `GET /calendar/calendars`. Works with `calendar.read` or `calendar.write`.
        public func calendars() async throws -> [NemiCalendar] {
            let list: CalendarList = try await client.get("calendar/calendars")
            return list.calendars
        }

        /// `GET /calendar/events` between `start` and `end`, optionally in one calendar.
        public func events(start: Date, end: Date, calendarId: String? = nil) async throws -> [NemiCalendarEvent] {
            let list: EventList = try await client.get("calendar/events", query: [
                "start": NemiDateFormat.string(from: start),
                "end": NemiDateFormat.string(from: end),
                "calendar_id": calendarId,
            ])
            return list.events
        }

        /// `POST /calendar/events`. Without `calendarId`, the primary Nemi calendar.
        public func create(
            title: String,
            start: Date,
            end: Date,
            calendarId: String? = nil,
            allDay: Bool? = nil,
            location: String? = nil,
            description: String? = nil,
            timezone: String? = nil,
            rrule: String? = nil
        ) async throws -> NemiCalendarEvent {
            try await create(NemiCalendarEventDraft(
                calendarId: calendarId, title: title, start: start, end: end, allDay: allDay,
                location: location, description: description, timezone: timezone, rrule: rrule
            ))
        }

        /// `POST /calendar/events`.
        public func create(_ draft: NemiCalendarEventDraft) async throws -> NemiCalendarEvent {
            guard draft.title != nil, draft.start != nil, draft.end != nil else {
                throw NemiAPIError(status: 400, code: .invalidRequest, message: "An event needs a title, start and end.")
            }
            return try await client.send("POST", "calendar/events", json: draft)
        }

        /// `PATCH /calendar/events/{id}`: only the non-nil fields change.
        public func update(id: String, _ changes: NemiCalendarEventDraft) async throws -> NemiCalendarEvent {
            try await client.send("PATCH", "calendar/events/\(id)", json: changes)
        }

        /// `DELETE /calendar/events/{id}`.
        public func delete(id: String) async throws {
            try await client.delete("calendar/events/\(id)")
        }
    }
}
