import Foundation

extension NemiClient {
    /// Gallery photos and albums. Needs `gallery.read` / `gallery.write`.
    public struct Gallery: Sendable {
        let client: NemiClient

        /// `GET /gallery/photos`: one page, newest first. `limit` is at most 100.
        public func photos(
            workspaceId: String? = nil,
            albumId: String? = nil,
            favorites: Bool? = nil,
            cursor: String? = nil,
            limit: Int? = nil
        ) async throws -> NemiPhotoPage {
            try await client.get("gallery/photos", query: [
                "workspace_id": workspaceId,
                "album_id": albumId,
                "favorites": favorites.map { $0 ? "true" : "false" },
                "cursor": cursor,
                "limit": limit.map { String(min(max($0, 1), 100)) },
            ])
        }

        /// Every photo, page by page, as an async sequence. Stops early when the
        /// consuming task is cancelled or the loop breaks.
        ///
        /// ```swift
        /// for try await photo in client.gallery.allPhotos(workspaceId: id) { ... }
        /// ```
        public func allPhotos(
            workspaceId: String? = nil,
            albumId: String? = nil,
            favorites: Bool? = nil,
            pageSize: Int = 100
        ) -> AsyncThrowingStream<NemiPhoto, Error> {
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        var cursor: String?
                        repeat {
                            try Task.checkCancellation()
                            let page = try await photos(
                                workspaceId: workspaceId, albumId: albumId, favorites: favorites,
                                cursor: cursor, limit: pageSize
                            )
                            for photo in page.photos { continuation.yield(photo) }
                            cursor = page.nextCursor
                        } while cursor != nil
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        /// `GET /gallery/photos/{id}`: includes the full-size `url` (15 minutes).
        public func photo(id: String) async throws -> NemiPhoto {
            try await client.get("gallery/photos/\(id)")
        }

        /// `GET /gallery/albums`.
        public func albums(workspaceId: String? = nil) async throws -> [NemiAlbum] {
            let list: AlbumList = try await client.get("gallery/albums", query: ["workspace_id": workspaceId])
            return list.albums
        }

        /// `POST /gallery/photos` (multipart). JPEG, PNG, HEIC, WebP or AVIF up to 50 MB.
        /// Nemi re-encodes the image. A photo already in the library throws `conflict` (409).
        ///
        /// - Parameter capturedAt: when the photo was taken, if the file has no EXIF date.
        public func upload(
            imageData: Data,
            fileName: String = "photo.jpg",
            mimeType: String? = nil,
            workspaceId: String? = nil,
            capturedAt: Date? = nil
        ) async throws -> NemiPhoto {
            guard Int64(imageData.count) <= Files.maxUploadSize else {
                throw NemiAPIError(status: 413, code: .tooLarge, message: "Photos can be at most 50 MB.")
            }
            let type = mimeType ?? Self.sniffImageType(imageData) ?? Files.mimeType(forFileName: fileName) ?? "application/octet-stream"
            let boundary = "NemiKit-\(UUID().uuidString)"
            var body = Data()
            func line(_ string: String) { body.append(Data((string + "\r\n").utf8)) }
            if let workspaceId {
                line("--\(boundary)")
                line("Content-Disposition: form-data; name=\"workspace_id\"")
                line("")
                line(workspaceId)
            }
            if let capturedAt {
                line("--\(boundary)")
                line("Content-Disposition: form-data; name=\"captured_at\"")
                line("")
                line(NemiDateFormat.string(from: capturedAt))
            }
            line("--\(boundary)")
            let safeName = fileName.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            line("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"")
            line("Content-Type: \(type)")
            line("")
            body.append(imageData)
            line("")
            line("--\(boundary)--")
            let data = try await client.perform("POST", "gallery/photos", query: [:], body: .multipart(body, boundary: boundary))
            return try await client.decode(NemiPhoto.self, from: data)
        }

        /// `POST /gallery/albums`. Without `workspaceId`, the person's own library.
        public func createAlbum(name: String, workspaceId: String? = nil) async throws -> NemiAlbum {
            struct Create: Encodable {
                let workspaceId: String?
                let name: String
                enum CodingKeys: String, CodingKey { case workspaceId = "workspace_id", name }
            }
            return try await client.send("POST", "gallery/albums", json: Create(workspaceId: workspaceId, name: name))
        }

        /// `POST /gallery/albums/{id}/photos` (up to 500 ids). Ids that are not
        /// photos in the album's library are counted in `skipped`.
        @discardableResult
        public func addPhotos(_ photoIds: [String], toAlbum albumId: String) async throws -> NemiAlbumAddResult {
            struct Add: Encodable {
                let photoIds: [String]
                enum CodingKeys: String, CodingKey { case photoIds = "photo_ids" }
            }
            return try await client.send("POST", "gallery/albums/\(albumId)/photos", json: Add(photoIds: photoIds))
        }

        /// `PATCH /gallery/photos/{id}`. Returns the updated photo (with `url` and `albums`).
        @discardableResult
        public func setFavorite(_ favorite: Bool, photoId: String) async throws -> NemiPhoto {
            struct Patch: Encodable { let favorite: Bool }
            return try await client.send("PATCH", "gallery/photos/\(photoId)", json: Patch(favorite: favorite))
        }

        static func sniffImageType(_ data: Data) -> String? {
            let bytes = [UInt8](data.prefix(12))
            if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
            if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
            if bytes.count >= 12, bytes[0...3] == [0x52, 0x49, 0x46, 0x46], bytes[8...11] == [0x57, 0x45, 0x42, 0x50] {
                return "image/webp"
            }
            if bytes.count >= 12, bytes[4...7] == [0x66, 0x74, 0x79, 0x70] {
                let brand = String(decoding: bytes[8...11], as: UTF8.self)
                if brand.hasPrefix("avi") { return "image/avif" }
                if ["heic", "heix", "mif1", "msf1", "heim", "heis"].contains(brand) { return "image/heic" }
            }
            return nil
        }
    }
}
