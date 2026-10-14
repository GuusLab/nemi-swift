import Foundation

/// An error from the Nemi REST API.
///
/// ```json
/// { "error": { "code": "insufficient_scope", "message": "This call needs files.read.", "required_scope": "files.read" } }
/// ```
public struct NemiAPIError: Error, Sendable, Equatable {
    /// The HTTP status.
    public let status: Int
    /// The machine-readable code.
    public let code: Code
    /// A human-readable message from the server.
    public let message: String
    /// For `insufficient_scope`: the scope the call needs. Sign in again asking for it.
    public let requiredScope: NemiScope?
    /// For `rate_limited`: seconds from `Retry-After`.
    public let retryAfter: TimeInterval?

    public init(status: Int, code: Code, message: String, requiredScope: NemiScope? = nil, retryAfter: TimeInterval? = nil) {
        self.status = status
        self.code = code
        self.message = message
        self.requiredScope = requiredScope
        self.retryAfter = retryAfter
    }

    /// An API error code. Unknown codes from newer servers are kept as is.
    public struct Code: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
        public var description: String { rawValue }

        public static let invalidRequest: Code = "invalid_request"
        public static let invalidToken: Code = "invalid_token"
        public static let insufficientScope: Code = "insufficient_scope"
        public static let forbidden: Code = "forbidden"
        public static let notFound: Code = "not_found"
        public static let conflict: Code = "conflict"
        public static let tooLarge: Code = "too_large"
        public static let rateLimited: Code = "rate_limited"
        public static let serverError: Code = "server_error"
        /// The upload URL refused the bytes (not a Nemi API response).
        public static let uploadFailed: Code = "upload_failed"

        /// The code the contract assigns to a status when the body has none.
        public static func forStatus(_ status: Int) -> Code {
            switch status {
            case 400: return .invalidRequest
            case 401: return .invalidToken
            case 403: return .forbidden
            case 404: return .notFound
            case 409: return .conflict
            case 413: return .tooLarge
            case 429: return .rateLimited
            default: return status >= 500 ? .serverError : Code(rawValue: "http_\(status)")
            }
        }
    }

    /// Builds an error from a non-2xx response.
    static func from(data: Data, response: HTTPURLResponse) -> NemiAPIError {
        struct Envelope: Decodable {
            struct Body: Decodable {
                let code: String?
                let message: String?
                let requiredScope: String?
            }
            let error: Body
        }
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(parseRetryAfter)
        let status = response.statusCode
        if let envelope = try? NemiJSON.makeDecoder().decode(Envelope.self, from: data) {
            return NemiAPIError(
                status: status,
                code: envelope.error.code.map { Code(rawValue: $0) } ?? .forStatus(status),
                message: envelope.error.message ?? HTTPURLResponse.localizedString(forStatusCode: status),
                requiredScope: envelope.error.requiredScope.map { NemiScope($0) },
                retryAfter: retryAfter
            )
        }
        let text = String(data: data.prefix(500), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NemiAPIError(
            status: status,
            code: .forStatus(status),
            message: (text?.isEmpty == false ? text : nil) ?? HTTPURLResponse.localizedString(forStatusCode: status),
            requiredScope: nil,
            retryAfter: retryAfter
        )
    }

    /// `Retry-After` as seconds or an HTTP date.
    static func parseRetryAfter(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let seconds = TimeInterval(trimmed) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: trimmed) { return max(0, date.timeIntervalSinceNow) }
        return nil
    }
}

extension NemiAPIError: LocalizedError {
    public var errorDescription: String? { message }
}
