import Foundation

/// Supplies bearer tokens to `NemiClient`. `NemiAuth` is the usual one.
public protocol NemiAccessTokenProvider: Sendable {
    /// A current access token, refreshed first when it is about to expire.
    func accessToken() async throws -> String
    /// Called when the API answered 401 for `rejected`. Return a new token to
    /// retry once, or `nil` to give up.
    func refreshAccessToken(rejected: String) async throws -> String?
}

/// A fixed access token (for scripts, tests, or tokens you manage yourself).
public struct StaticAccessTokenProvider: NemiAccessTokenProvider {
    public let token: String
    public init(_ token: String) { self.token = token }
    public func accessToken() async throws -> String { token }
    public func refreshAccessToken(rejected: String) async throws -> String? { nil }
}
