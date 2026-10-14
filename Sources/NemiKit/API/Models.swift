import Foundation

// Property names follow `convertFromSnakeCase`: `upload_url` decodes into
// `uploadUrl`, not `uploadURL`. Shapes follow DEVELOPER_PLATFORM.md and the
// v1 routes; fields the server may send as null are optional.

// MARK: Account

/// `GET /me`. `id` is the pairwise subject (the id_token's `sub`).
public struct NemiUser: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String?
    /// The Nemi username (`preferred_username`).
    public let username: String?
    public let picture: URL?
    public let email: String?
    public let emailVerified: Bool?

    enum CodingKeys: String, CodingKey { case id, name, username, preferredUsername, picture, email, emailVerified }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        username = try c.decodeIfPresent(String.self, forKey: .preferredUsername)
            ?? c.decodeIfPresent(String.self, forKey: .username)
        picture = try? c.decodeIfPresent(URL.self, forKey: .picture)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        emailVerified = try c.decodeIfPresent(Bool.self, forKey: .emailVerified)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(username, forKey: .preferredUsername)
        try c.encodeIfPresent(picture, forKey: .picture)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encodeIfPresent(emailVerified, forKey: .emailVerified)
    }
}

/// A workspace and the person's role in it (`owner`, or the member role).
public struct NemiWorkspace: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let role: String
}

struct WorkspaceList: Decodable { let workspaces: [NemiWorkspace] }

// MARK: Files

/// A file in Drive.
public struct NemiFile: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let size: Int64
    /// MIME type, when known.
    public let type: String?
    public let workspaceId: String?
    /// `nil` at the top level of the workspace.
    public let folderId: String?
    public let createdAt: Date?
}

/// A folder. `workspaceId` and `parentId` are only filled in by `folders.create`.
public struct NemiFolder: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let workspaceId: String?
    /// `nil` at the top level.
    public let parentId: String?
}

/// `GET /files`: the folders and files in one folder.
public struct NemiFileListing: Codable, Sendable, Equatable {
    public let folders: [NemiFolder]
    public let files: [NemiFile]
}

struct FileList: Decodable { let files: [NemiFile] }

/// A short-lived link that works without a token.
public struct NemiDownloadLink: Codable, Sendable, Equatable {
    /// Works for 15 minutes. Never send the bearer token to it.
    public let url: URL
    public let expiresAt: Date
}

/// `POST /files/uploads`: where and how to PUT the bytes.
public struct NemiUploadTicket: Codable, Sendable, Equatable {
    public let uploadId: String
    public let uploadUrl: URL
    /// Always `PUT`.
    public let method: String
    /// Headers the PUT must carry (for example `Content-Type`).
    public let headers: [String: String]
    /// The largest accepted body in bytes, or 0 when the server sets no limit here.
    public let maxSize: Int64
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey { case uploadId, uploadUrl, method, headers, maxSize, expiresAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uploadId = try c.decode(String.self, forKey: .uploadId)
        uploadUrl = try c.decode(URL.self, forKey: .uploadUrl)
        method = try c.decodeIfPresent(String.self, forKey: .method) ?? "PUT"
        // Header names are data, not keys to camelCase: decode the raw object.
        let rawHeaders = (try? c.decodeIfPresent([String: JSONValue].self, forKey: .headers)) ?? nil
        headers = (rawHeaders ?? [:]).compactMapValues { value in
            switch value {
            case .string(let string): return string
            case .number(let number): return number.rounded() == number ? String(Int64(number)) : String(number)
            case .bool(let bool): return bool ? "true" : "false"
            default: return nil
            }
        }
        maxSize = try c.decodeIfPresent(Int64.self, forKey: .maxSize) ?? 0
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
    }
}

/// Where to move a file.
public enum NemiFolderDestination: Sendable, Equatable {
    /// The top level of the workspace.
    case root
    case folder(String)
}

// MARK: Gallery

/// A photo. Image URLs expire after 15 minutes: fetch again rather than storing them.
public struct NemiPhoto: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let workspaceId: String?
    public let name: String?
    public let width: Int
    public let height: Int
    public let size: Int64
    /// When the camera took it, or else when it was uploaded.
    public let capturedAt: Date?
    public let favorite: Bool
    /// Average color as `#rrggbb`, handy as a placeholder while the thumbnail loads.
    public let color: String?
    public let thumbnailUrl: URL?
    /// Full size. Only on `gallery.photo(id:)` and `gallery.setFavorite`.
    public let url: URL?
    /// The albums the photo is in. Only on the single-photo answers.
    public let albums: [NemiAlbumReference]?
}

/// An album a photo belongs to.
public struct NemiAlbumReference: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
}

/// One page of photos, newest first.
public struct NemiPhotoPage: Codable, Sendable, Equatable {
    public let photos: [NemiPhoto]
    /// Pass to the next call. `nil` on the last page.
    public let nextCursor: String?
}

/// A photo album.
public struct NemiAlbum: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let count: Int
    /// Thumbnail of the cover photo (expires like every image URL).
    public let coverUrl: URL?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        coverUrl = try? c.decodeIfPresent(URL.self, forKey: .coverUrl)
    }
}

struct AlbumList: Decodable { let albums: [NemiAlbum] }

/// `POST /gallery/albums/{id}/photos`.
public struct NemiAlbumAddResult: Codable, Sendable, Equatable {
    public let albumId: String
    /// Photos newly added.
    public let added: Int
    /// Ids that are not photos in the album's library.
    public let skipped: Int
}

// MARK: Docs

/// A Doc. `markdown` is only present on `docs.get`, `create` and `update`.
public struct NemiDocument: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// A short plain-text preview.
    public let preview: String?
    public let markdown: String?
    public let workspaceId: String?
    public let updatedAt: Date?
}

/// How `docs.update` applies `markdown`.
public enum NemiDocUpdateMode: String, Sendable, Codable {
    case replace
    case append
}

struct DocList: Decodable { let docs: [NemiDocument] }

// MARK: Sheets

/// A Sheet. `rows`, `cols` and `cells` (first tab, keyed by A1 references)
/// are only present on `sheets.get` and `sheets.create`.
public struct NemiSheet: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let workspaceId: String?
    public let updatedAt: Date?
    public let rows: Int?
    public let cols: Int?
    public let cells: [String: NemiSheetCell]?
}

/// One cell as read: the stored `value` and the text the grid shows.
///
/// Write cells with plain `JSONValue`s through `sheets.updateCells`.
public struct NemiSheetCell: Codable, Sendable, Equatable {
    /// What is stored: text, a number, a boolean, or a formula string such as `=SUM(A1:A3)`.
    public let value: JSONValue
    /// The formatted text shown in the grid (the result, for a formula).
    public let display: String?

    public init(value: JSONValue, display: String? = nil) {
        self.value = value
        self.display = display
    }

    enum CodingKeys: String, CodingKey { case value, display }

    public init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self), c.contains(.value) || c.contains(.display) {
            value = try c.decodeIfPresent(JSONValue.self, forKey: .value) ?? .null
            display = try c.decodeIfPresent(String.self, forKey: .display)
        } else {
            // Tolerate a bare value.
            value = try decoder.singleValueContainer().decode(JSONValue.self)
            display = nil
        }
    }

    /// `display` when present, else the value as text.
    public var text: String {
        if let display { return display }
        switch value {
        case .string(let string): return string
        case .number(let number): return number.rounded() == number && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        case .bool(let bool): return bool ? "TRUE" : "FALSE"
        default: return ""
        }
    }
}

struct SheetList: Decodable { let sheets: [NemiSheet] }

/// `PATCH /sheets/{id}/cells`.
public struct NemiSheetCellsUpdate: Codable, Sendable, Equatable {
    public let id: String
    /// How many cells were written.
    public let updated: Int
}

// MARK: Forms

/// A Form. Lists carry the summary fields; `forms.get` and `forms.create`
/// add the questions and settings. Everything sent is also in `raw`.
public struct NemiForm: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let description: String?
    /// Whether it accepts responses through a public link.
    public let published: Bool?
    public let workspaceId: String?
    public let updatedAt: Date?
    /// The questions, as in the Nemi docs.
    public let fields: [JSONValue]?
    public let responseCount: Int?
    /// The public link, when published.
    public let respondUrl: URL?
    /// The whole object as sent, keys unchanged.
    public let raw: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case id, formId, title, description, published, workspaceId, updatedAt, fields, responseCount, respondUrl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try c.decodeIfPresent(String.self, forKey: .id) ?? c.decodeIfPresent(String.self, forKey: .formId) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "A form needs id or form_id."))
        }
        self.id = id
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description)
        published = try c.decodeIfPresent(Bool.self, forKey: .published)
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        fields = try? c.decodeIfPresent([JSONValue].self, forKey: .fields)
        responseCount = try? c.decodeIfPresent(Int.self, forKey: .responseCount)
        respondUrl = try? c.decodeIfPresent(URL.self, forKey: .respondUrl)
        raw = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }
}

struct FormList: Decodable { let forms: [NemiForm] }

/// One submission: answers keyed by the response sheet's column headers
/// (usually the question titles), newest first.
public struct NemiFormResponse: Decodable, Sendable, Equatable {
    public let values: [String: JSONValue]

    public init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }

    /// The answer in the column titled `column`.
    public subscript(column: String) -> String? { values[column]?.stringValue }
}

/// `GET /forms/{id}/responses`.
public struct NemiFormResponsePage: Decodable, Sendable, Equatable {
    public let formId: String
    /// All responses, not only this page.
    public let total: Int
    public let responses: [NemiFormResponse]
}

// MARK: Canvas

/// A Canvas board. Lists and `canvas.create` carry the summary; `canvas.get`
/// and `canvas.update` add the elements.
/// Everything sent is also in `raw`.
public struct NemiCanvas: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let workspaceId: String?
    public let updatedAt: Date?
    public let elementCount: Int?
    /// Shapes and text (and strokes when asked for).
    public let elements: [JSONValue]?
    /// The whole object as sent, keys unchanged.
    public let raw: [String: JSONValue]

    enum CodingKeys: String, CodingKey { case id, canvasId, title, workspaceId, updatedAt, elementCount, elements }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try c.decodeIfPresent(String.self, forKey: .id) ?? c.decodeIfPresent(String.self, forKey: .canvasId) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "A canvas needs id or canvas_id."))
        }
        self.id = id
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        elementCount = try? c.decodeIfPresent(Int.self, forKey: .elementCount)
        elements = try? c.decodeIfPresent([JSONValue].self, forKey: .elements)
        raw = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }
}

struct CanvasList: Decodable { let canvases: [NemiCanvas] }

// MARK: Calendar

/// A calendar made in Nemi.
public struct NemiCalendar: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let color: String?
    /// IANA time zone, for example `Europe/Amsterdam`.
    public let timezone: String?
    /// New events without a `calendarId` go here.
    public let primary: Bool
}

struct CalendarList: Decodable { let calendars: [NemiCalendar] }

/// An event in a calendar made in Nemi. Events synced from Google, Outlook
/// and other providers are never part of the API.
public struct NemiCalendarEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let calendarId: String?
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool
    public let location: String?
    public let description: String?
    public let timezone: String?
    /// RFC 5545 recurrence rule, for example `FREQ=WEEKLY;BYDAY=MO`.
    public let rrule: String?

    enum CodingKeys: String, CodingKey { case id, calendarId, title, start, end, allDay, location, description, timezone, rrule }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        calendarId = try c.decodeIfPresent(String.self, forKey: .calendarId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        location = try c.decodeIfPresent(String.self, forKey: .location)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone)
        rrule = try c.decodeIfPresent(String.self, forKey: .rrule)
    }
}

struct EventList: Decodable { let events: [NemiCalendarEvent] }

/// The fields for creating or changing an event. `nil` fields are left out.
public struct NemiCalendarEventDraft: Encodable, Sendable, Equatable {
    /// Leave `nil` on create to use the person's primary Nemi calendar.
    public var calendarId: String?
    public var title: String?
    public var start: Date?
    public var end: Date?
    public var allDay: Bool?
    public var location: String?
    public var description: String?
    /// IANA time zone.
    public var timezone: String?
    /// RFC 5545 recurrence rule.
    public var rrule: String?

    public init(
        calendarId: String? = nil,
        title: String? = nil,
        start: Date? = nil,
        end: Date? = nil,
        allDay: Bool? = nil,
        location: String? = nil,
        description: String? = nil,
        timezone: String? = nil,
        rrule: String? = nil
    ) {
        self.calendarId = calendarId
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.location = location
        self.description = description
        self.timezone = timezone
        self.rrule = rrule
    }

    enum CodingKeys: String, CodingKey {
        case title, start, end, location, description, timezone, rrule
        case calendarId = "calendar_id"
        case allDay = "all_day"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(calendarId, forKey: .calendarId)
        try c.encodeIfPresent(title, forKey: .title)
        // All-day events travel as dates, everything else as ISO 8601 instants.
        let dateOnly = allDay == true
        let format: (Date) -> String = { date in
            dateOnly ? NemiDateFormat.dateOnlyString(from: date) : NemiDateFormat.string(from: date)
        }
        try c.encodeIfPresent(start.map(format), forKey: .start)
        try c.encodeIfPresent(end.map(format), forKey: .end)
        try c.encodeIfPresent(allDay, forKey: .allDay)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(timezone, forKey: .timezone)
        try c.encodeIfPresent(rrule, forKey: .rrule)
    }
}
