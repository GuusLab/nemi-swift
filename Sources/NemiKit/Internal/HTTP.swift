import Foundation

/// Thin wrapper over `URLSession` so every network call goes through one place.
struct HTTPTransport: Sendable {
    let session: URLSession

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    func upload(_ request: URLRequest, data: Data) async throws -> (Data, HTTPURLResponse) {
        let (body, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (body, http)
    }

    func upload(_ request: URLRequest, fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        let (body, response) = try await session.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (body, http)
    }
}

extension URL {
    /// Appends a path like `files/abc/download`, escaping each segment.
    func appendingAPIPath(_ path: String) -> URL {
        var url = self
        for segment in path.split(separator: "/") {
            url.appendPathComponent(String(segment))
        }
        return url
    }
}

let nemiUserAgent = "NemiKit/\(NemiKit.version)"
