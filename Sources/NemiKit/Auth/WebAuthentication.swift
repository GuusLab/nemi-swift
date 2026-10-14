#if canImport(AuthenticationServices) && !os(tvOS) && !os(watchOS)
import AuthenticationServices
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension NemiAuth {
    /// Signs the person in with `ASWebAuthenticationSession` and stores the session.
    ///
    /// - Parameters:
    ///   - scopes: the scopes to ask for. `openid` is always added. Add
    ///     `.offlineAccess` to get a refresh token.
    ///   - presentationAnchor: the window to present from. `nil` uses the key window.
    ///   - prefersEphemeralSession: `true` does not share cookies with Safari, so
    ///     the person signs in to Nemi every time and no "wants to use nemilab.com
    ///     to sign in" alert is shown.
    ///   - prompt: `"consent"` always shows the consent screen.
    /// - Throws: `NemiAuthError.cancelled` when the person closes the sheet.
    @MainActor
    @discardableResult
    public func signIn(
        scopes: [NemiScope] = NemiScope.defaultSignIn,
        presentationAnchor: ASPresentationAnchor? = nil,
        prefersEphemeralSession: Bool = false,
        prompt: String? = nil
    ) async throws -> NemiSession {
        let request = try await makeAuthorizationRequest(scopes: scopes, prompt: prompt)
        let authenticator = WebAuthenticator(anchor: presentationAnchor)
        let callbackURL = try await authenticator.authenticate(
            url: request.url,
            redirectURI: redirectURI,
            prefersEphemeralSession: prefersEphemeralSession
        )
        return try await completeAuthorization(callbackURL: callbackURL, request: request)
    }
}

/// Owns one `ASWebAuthenticationSession` for its whole lifetime. The session is
/// held strongly until the callback fires; a released session never calls back.
@MainActor
final class WebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor?
    private var session: ASWebAuthenticationSession?

    init(anchor: ASPresentationAnchor?) {
        self.anchor = anchor
    }

    func authenticate(url: URL, redirectURI: URL, prefersEphemeralSession: Bool) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let completion: @Sendable (URL?, Error?) -> Void = { callbackURL, error in
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        continuation.resume(throwing: NemiAuthError.cancelled)
                    } else if let error {
                        continuation.resume(throwing: NemiAuthError.presentationFailed(error.localizedDescription))
                    } else {
                        continuation.resume(throwing: NemiAuthError.missingAuthorizationCode)
                    }
                }
                let session = Self.makeSession(url: url, redirectURI: redirectURI, completion: completion)
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = prefersEphemeralSession
                self.session = session
                if !session.start() {
                    self.session = nil
                    continuation.resume(throwing: NemiAuthError.presentationFailed("The sign-in sheet could not be started."))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.session?.cancel() }
        }
    }

    private static func makeSession(
        url: URL,
        redirectURI: URL,
        completion: @escaping @Sendable (URL?, Error?) -> Void
    ) -> ASWebAuthenticationSession {
        let scheme = redirectURI.scheme?.lowercased() ?? ""
        if #available(iOS 17.4, macOS 14.4, visionOS 1.1, *) {
            if scheme == "https", let host = redirectURI.host {
                let path = redirectURI.path.isEmpty ? "/" : redirectURI.path
                return ASWebAuthenticationSession(url: url, callback: .https(host: host, path: path), completionHandler: completion)
            }
            return ASWebAuthenticationSession(url: url, callback: .customScheme(scheme), completionHandler: completion)
        }
        // Before iOS 17.4 an https callback can only be caught as a universal link
        // handled by the app; the custom scheme path is the reliable one there.
        return ASWebAuthenticationSession(url: url, callbackURLScheme: scheme, completionHandler: completion)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            if let anchor { return anchor }
            #if canImport(UIKit)
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            if let key = windows.first(where: \.isKeyWindow) ?? windows.first { return key }
            return ASPresentationAnchor()
            #elseif canImport(AppKit)
            return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
            #else
            return ASPresentationAnchor()
            #endif
        }
    }
}
#endif
