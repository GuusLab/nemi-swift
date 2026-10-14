import Foundation

/// NemiKit: Sign in with Nemi and the Nemi REST API.
public enum NemiKit {
    /// The SDK version, sent in the `User-Agent` header.
    public static let version = "0.1.0"

    /// The production OAuth / OIDC issuer.
    public static let defaultIssuer = URL(string: "https://nemilab.com/oauth")!

    /// The production REST API base URL.
    public static let defaultAPIBaseURL = URL(string: "https://nemilab.com/api/v1")!
}
