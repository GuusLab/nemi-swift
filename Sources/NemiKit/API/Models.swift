import Foundation

// Property names follow `convertFromSnakeCase`: `upload_url` decodes into
// `uploadUrl`, not `uploadURL`.

// MARK: Account

/// `GET /me`. `id` is the pairwise subject (the id_token's `sub`).
public struct NemiUser: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String?
    public let username: String?
    public let picture: URL?
    public let email: String?
    public let emailVerified: Bool?
}

/// A workspace and the person's role in it.
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
    /// MIME type.
    public let type: String
    public let workspaceId: String
    /// `nil` at the top level of the workspace.
    public let folderId: String?
    public let createdAt: Date
}

/// A folder.
public struct NemiFolder: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
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

/// `POST /files/uploads`: where to PUT the bytes.
public struct NemiUploadTicket: Codable, Sendable, Equatable {
    public let uploadId: String
    public let uploadUrl: URL
    /// Always `PUT`.
    public let method: String
    public let expiresAt: Date
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
    public let name: String?
    public let width: Int
    public let height: Int
    public let size: Int64
    public let capturedAt: Date?
    public let favorite: Bool
    public let thumbnailUrl: URL?
    /// Full size. Only on `gallery.photo(id:)`.
    public let url: URL?
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }
}

struct AlbumList: Decodable { let albums: [NemiAlbum] }

// MARK: Docs, Sheets, Forms, Canvas

/// A Doc. `markdown` is only present on `docs.get` and after a write.
public struct NemiDocument: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let markdown: String?
    public let workspaceId: String?
    public let updatedAt: Date?
}

/// A Sheet. `cells` is keyed by A1 references and only present on `sheets.get`.
public struct NemiSheet: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let cells: [String: JSONValue]?
    public let workspaceId: String?
    public let updatedAt: Date?
}

/// A Form. The contract does not fix the shape of a form beyond its id and
/// title yet, so everything the server sends is also available in `raw` with
/// the original keys.
public struct NemiForm: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String?
    public let workspaceId: String?
    public let updatedAt: Date?
    public let fields: [JSONValue]?
    /// The whole object as sent, keys unchanged.
    public let raw: [String: JSONValue]

    enum CodingKeys: String, CodingKey { case id, title, workspaceId, updatedAt, fields }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        fields = try? c.decodeIfPresent([JSONValue].self, forKey: .fields)
        raw = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }
}

/// One response to a Form. Provisional shape: see `raw`.
public struct NemiFormResponse: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let submittedAt: Date?
    /// Answers keyed by field id, when the server sends them that way.
    public let answers: [String: JSONValue]?
    /// The whole object as sent, keys unchanged.
    public let raw: [String: JSONValue]

    enum CodingKeys: String, CodingKey { case id, submittedAt, createdAt, answers }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        submittedAt = (try? c.decodeIfPresent(Date.self, forKey: .submittedAt))
            ?? (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil
        answers = try? c.decodeIfPresent([String: JSONValue].self, forKey: .answers)
        raw = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }
}

/// A Canvas board. Provisional shape: see `raw`.
public struct NemiCanvas: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String?
    public let workspaceId: String?
    public let updatedAt: Date?
    /// The whole object as sent, keys unchanged.
    public let raw: [String: JSONValue]

    enum CodingKeys: String, CodingKey { case id, title, name, workspaceId, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? c.decodeIfPresent(String.self, forKey: .name)
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        raw = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }
}

// MARK: Calendar

/// An event in a calendar made in Nemi. Events synced from Google, Outlook
/// and other providers are never part of the API.
public struct NemiCalendarEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// For all-day events a `YYYY-MM-DD` value decodes as midnight UTC.
    public let start: Date
    public let end: Date
    public let allDay: Bool?
    public let location: String?
    public let description: String?
}

/// The fields for creating or changing an event. `nil` fields are left out.
public struct NemiCalendarEventDraft: Encodable, Sendable, Equatable {
    public var title: String?
    public var start: Date?
    public var end: Date?
    public var allDay: Bool?
    public var location: String?
    public var description: String?

    public init(title: String? = nil, start: Date? = nil, end: Date? = nil, allDay: Bool? = nil, location: String? = nil, description: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.location = location
        self.description = description
    }

    enum CodingKeys: String, CodingKey {
        case title, start, end, location, description
        case allDay = "all_day"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
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
    }
}
