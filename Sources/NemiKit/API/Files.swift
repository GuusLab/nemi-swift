import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

extension NemiClient {
    /// Drive files. Needs `files.read` / `files.write`.
    public struct Files: Sendable {
        let client: NemiClient

        /// The largest file the API accepts.
        public static let maxUploadSize: Int64 = 50 * 1024 * 1024

        /// `GET /files`: the folders and files in a folder. Omit `folderId` for the top level.
        public func list(workspaceId: String, folderId: String? = nil, limit: Int? = nil) async throws -> NemiFileListing {
            try await client.get("files", query: [
                "workspace_id": workspaceId,
                "folder_id": folderId,
                "limit": limit.map(String.init),
            ])
        }

        /// `GET /files/search`.
        public func search(_ query: String, workspaceId: String? = nil, limit: Int? = nil) async throws -> [NemiFile] {
            let list: FileList = try await client.get("files/search", query: [
                "q": query,
                "workspace_id": workspaceId,
                "limit": limit.map(String.init),
            ])
            return list.files
        }

        /// `GET /files/{id}`.
        public func get(id: String) async throws -> NemiFile {
            try await client.get("files/\(id)")
        }

        /// `GET /files/{id}/download`: a link that works for 15 minutes without a token.
        public func downloadURL(id: String) async throws -> NemiDownloadLink {
            try await client.get("files/\(id)/download")
        }

        /// Uploads bytes: creates an upload, PUTs the bytes, completes it.
        public func upload(
            data: Data,
            name: String,
            type: String? = nil,
            workspaceId: String,
            folderId: String? = nil
        ) async throws -> NemiFile {
            try await upload(
                source: .data(data),
                size: Int64(data.count),
                name: name,
                type: type ?? Self.mimeType(forFileName: name),
                workspaceId: workspaceId,
                folderId: folderId
            )
        }

        /// Uploads a file from disk without loading it into memory. `name` defaults to the file name.
        public func upload(
            fileURL: URL,
            name: String? = nil,
            type: String? = nil,
            workspaceId: String,
            folderId: String? = nil
        ) async throws -> NemiFile {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let fileName = name ?? fileURL.lastPathComponent
            return try await upload(
                source: .file(fileURL),
                size: size,
                name: fileName,
                type: type ?? Self.mimeType(forFileName: fileName),
                workspaceId: workspaceId,
                folderId: folderId
            )
        }

        enum Source { case data(Data), file(URL) }

        private func upload(source: Source, size: Int64, name: String, type: String?, workspaceId: String, folderId: String?) async throws -> NemiFile {
            guard size <= Self.maxUploadSize else {
                throw NemiAPIError(status: 413, code: .tooLarge, message: "Files can be at most 50 MB.")
            }
            struct Create: Encodable {
                let workspaceId: String
                let folderId: String?
                let name: String
                let type: String?
                let size: Int64
                enum CodingKeys: String, CodingKey {
                    case workspaceId = "workspace_id", folderId = "folder_id", name, type, size
                }
            }
            let ticket: NemiUploadTicket = try await client.send(
                "POST", "files/uploads",
                json: Create(workspaceId: workspaceId, folderId: folderId, name: name, type: type, size: size)
            )

            // The upload URL is presigned: it must never see the bearer token.
            var put = URLRequest(url: ticket.uploadUrl)
            put.httpMethod = ticket.method.isEmpty ? "PUT" : ticket.method.uppercased()
            if let type { put.setValue(type, forHTTPHeaderField: "Content-Type") }
            let (body, response): (Data, HTTPURLResponse)
            switch source {
            case .data(let data): (body, response) = try await client.transport.upload(put, data: data)
            case .file(let url): (body, response) = try await client.transport.upload(put, fileURL: url)
            }
            guard (200..<300).contains(response.statusCode) else {
                throw NemiAPIError(
                    status: response.statusCode,
                    code: .uploadFailed,
                    message: String(data: body.prefix(300), encoding: .utf8) ?? "The upload was refused."
                )
            }

            struct Empty: Encodable {}
            return try await client.send("POST", "files/uploads/\(ticket.uploadId)/complete", json: Empty())
        }

        /// `PATCH /files/{id}`: rename and/or move.
        public func update(id: String, name: String? = nil, moveTo destination: NemiFolderDestination? = nil) async throws -> NemiFile {
            struct Patch: Encodable {
                let name: String?
                let destination: NemiFolderDestination?
                enum CodingKeys: String, CodingKey { case name, folderId = "folder_id" }
                func encode(to encoder: Encoder) throws {
                    var c = encoder.container(keyedBy: CodingKeys.self)
                    try c.encodeIfPresent(name, forKey: .name)
                    switch destination {
                    case .none: break
                    case .root: try c.encodeNil(forKey: .folderId)
                    case .folder(let id): try c.encode(id, forKey: .folderId)
                    }
                }
            }
            return try await client.send("PATCH", "files/\(id)", json: Patch(name: name, destination: destination))
        }

        /// `DELETE /files/{id}`. Moves to trash where the plan has one.
        public func delete(id: String) async throws {
            try await client.perform("DELETE", "files/\(id)", query: [:], body: .none)
        }

        static func mimeType(forFileName name: String) -> String? {
            #if canImport(UniformTypeIdentifiers)
            let ext = (name as NSString).pathExtension
            guard !ext.isEmpty else { return nil }
            return UTType(filenameExtension: ext)?.preferredMIMEType
            #else
            return nil
            #endif
        }
    }

    /// Drive folders. Needs `files.write`.
    public struct Folders: Sendable {
        let client: NemiClient

        /// `POST /folders`. Omit `parentId` for the top level.
        public func create(name: String, workspaceId: String, parentId: String? = nil) async throws -> NemiFolder {
            struct Create: Encodable {
                let workspaceId: String
                let name: String
                let parentId: String?
                enum CodingKeys: String, CodingKey { case workspaceId = "workspace_id", name, parentId = "parent_id" }
            }
            return try await client.send("POST", "folders", json: Create(workspaceId: workspaceId, name: name, parentId: parentId))
        }
    }
}
