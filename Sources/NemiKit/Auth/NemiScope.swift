import Foundation

/// The `prompt` values the Nemi authorize endpoint supports.
public enum NemiPrompt: String, Sendable, Equatable {
    /// Always show the consent screen, even when every scope was granted before.
    case consent
    /// Never show any screen. Fails with `login_required` (not signed in to Nemi)
    /// or `consent_required` (scopes not granted yet), surfaced as
    /// `NemiAuthError.authorizationFailed`. Useful for a silent re-check.
    case none
}

/// An OAuth scope. Use the static constants, or `NemiScope("custom")` for a
/// scope this SDK version does not know about yet.
public struct NemiScope: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    /// An `id_token`. Always added by `NemiAuth.signIn`.
    public static let openid: NemiScope = "openid"
    /// Name, username and avatar URL.
    public static let profile: NemiScope = "profile"
    /// Email address and whether it is verified.
    public static let email: NemiScope = "email"
    /// A refresh token. Without it the session ends when the access token expires.
    public static let offlineAccess: NemiScope = "offline_access"

    public static let filesRead: NemiScope = "files.read"
    public static let filesWrite: NemiScope = "files.write"
    public static let galleryRead: NemiScope = "gallery.read"
    public static let galleryWrite: NemiScope = "gallery.write"
    public static let docsRead: NemiScope = "docs.read"
    public static let docsWrite: NemiScope = "docs.write"
    public static let sheetsRead: NemiScope = "sheets.read"
    public static let sheetsWrite: NemiScope = "sheets.write"
    public static let formsRead: NemiScope = "forms.read"
    public static let formsWrite: NemiScope = "forms.write"
    public static let canvasRead: NemiScope = "canvas.read"
    public static let canvasWrite: NemiScope = "canvas.write"
    public static let calendarRead: NemiScope = "calendar.read"
    public static let calendarWrite: NemiScope = "calendar.write"

    /// `openid profile email offline_access`.
    public static let defaultSignIn: [NemiScope] = [.openid, .profile, .email, .offlineAccess]

    /// Parses a space-separated scope string.
    static func parse(_ string: String?) -> [NemiScope] {
        (string ?? "").split(separator: " ").map { NemiScope(String($0)) }
    }
}
