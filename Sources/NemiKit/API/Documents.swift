import Foundation

extension NemiClient {
    /// Docs as Markdown. Needs `docs.read` / `docs.write`.
    public struct Docs: Sendable {
        let client: NemiClient

        /// `GET /docs`.
        public func list(workspaceId: String? = nil) async throws -> [NemiDocument] {
            try await client.list("docs", query: ["workspace_id": workspaceId], keys: ["docs", "documents", "items"])
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

        /// `PATCH /docs/{id}`.
        public func update(id: String, title: String? = nil, markdown: String? = nil) async throws -> NemiDocument {
            struct Patch: Encodable { let title: String?; let markdown: String? }
            return try await client.send("PATCH", "docs/\(id)", json: Patch(title: title, markdown: markdown))
        }

        /// `DELETE /docs/{id}`.
        public func delete(id: String) async throws {
            try await client.perform("DELETE", "docs/\(id)", query: [:], body: .none)
        }
    }

    /// Sheets as cells. Needs `sheets.read` / `sheets.write`.
    public struct Sheets: Sendable {
        let client: NemiClient

        /// `GET /sheets`.
        public func list(workspaceId: String? = nil) async throws -> [NemiSheet] {
            try await client.list("sheets", query: ["workspace_id": workspaceId], keys: ["sheets", "items"])
        }

        /// `GET /sheets/{id}`: includes `cells` keyed by A1 references.
        public func get(id: String) async throws -> NemiSheet {
            try await client.get("sheets/\(id)")
        }

        /// `POST /sheets`.
        public func create(title: String, workspaceId: String? = nil) async throws -> NemiSheet {
            struct Create: Encodable {
                let workspaceId: String?
                let title: String
                enum CodingKeys: String, CodingKey { case workspaceId = "workspace_id", title }
            }
            return try await client.send("POST", "sheets", json: Create(workspaceId: workspaceId, title: title))
        }

        /// `PATCH /sheets/{id}/cells`. Keys are A1 references; `.null` clears a cell.
        ///
        /// ```swift
        /// try await client.sheets.updateCells(id: id, cells: ["A1": "Name", "B1": 42])
        /// ```
        public func updateCells(id: String, cells: [String: JSONValue]) async throws {
            struct Patch: Encodable { let cells: [String: JSONValue] }
            try await client.sendDiscarding("PATCH", "sheets/\(id)/cells", json: Patch(cells: cells))
        }

        /// `DELETE /sheets/{id}`.
        public func delete(id: String) async throws {
            try await client.perform("DELETE", "sheets/\(id)", query: [:], body: .none)
        }
    }

    /// Forms and their responses. Needs `forms.read` / `forms.write`.
    public struct Forms: Sendable {
        let client: NemiClient

        /// `GET /forms`.
        public func list(workspaceId: String? = nil) async throws -> [NemiForm] {
            try await client.list("forms", query: ["workspace_id": workspaceId], keys: ["forms", "items"])
        }

        /// `GET /forms/{id}`.
        public func get(id: String) async throws -> NemiForm {
            try await client.get("forms/\(id)")
        }

        /// `GET /forms/{id}/responses`.
        public func responses(formId: String) async throws -> [NemiFormResponse] {
            try await client.list("forms/\(formId)/responses", keys: ["responses", "items"])
        }

        /// `POST /forms`. `fields` is passed through as JSON.
        public func create(title: String, fields: [JSONValue]? = nil, workspaceId: String? = nil) async throws -> NemiForm {
            struct Create: Encodable {
                let workspaceId: String?
                let title: String
                let fields: [JSONValue]?
                enum CodingKeys: String, CodingKey { case workspaceId = "workspace_id", title, fields }
            }
            return try await client.send("POST", "forms", json: Create(workspaceId: workspaceId, title: title, fields: fields))
        }

        /// `DELETE /forms/{id}`.
        public func delete(id: String) async throws {
            try await client.perform("DELETE", "forms/\(id)", query: [:], body: .none)
        }
    }

    /// Canvas boards (read only). Needs `canvas.read`.
    public struct Canvas: Sendable {
        let client: NemiClient

        /// `GET /canvas`.
        public func list(workspaceId: String? = nil) async throws -> [NemiCanvas] {
            try await client.list("canvas", query: ["workspace_id": workspaceId], keys: ["canvases", "canvas", "boards", "items"])
        }

        /// `GET /canvas/{id}`.
        public func get(id: String) async throws -> NemiCanvas {
            try await client.get("canvas/\(id)")
        }
    }

    /// Calendars made in Nemi. Needs `calendar.read` / `calendar.write`.
    public struct Calendar: Sendable {
        let client: NemiClient

        /// `GET /calendar/events` between `start` and `end`.
        public func events(start: Date, end: Date) async throws -> [NemiCalendarEvent] {
            try await client.list("calendar/events", query: [
                "start": NemiDateFormat.string(from: start),
                "end": NemiDateFormat.string(from: end),
            ], keys: ["events", "items"])
        }

        /// `POST /calendar/events`.
        public func create(title: String, start: Date, end: Date, allDay: Bool? = nil, location: String? = nil, description: String? = nil) async throws -> NemiCalendarEvent {
            try await create(NemiCalendarEventDraft(title: title, start: start, end: end, allDay: allDay, location: location, description: description))
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
            try await client.perform("DELETE", "calendar/events/\(id)", query: [:], body: .none)
        }
    }
}
