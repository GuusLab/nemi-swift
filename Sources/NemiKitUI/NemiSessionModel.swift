#if canImport(SwiftUI)
import Foundation
import NemiKit
import SwiftUI
#if canImport(AuthenticationServices) && !os(tvOS) && !os(watchOS)
import AuthenticationServices
#endif

/// Observable sign-in state for SwiftUI.
///
/// ```swift
/// @StateObject private var model = NemiSessionModel(auth: auth)
///
/// var body: some View {
///     if model.isSignedIn { Home(client: model.client) }
///     else { SignInWithNemiButton { Task { await model.signIn() } } }
/// }
/// .task { await model.restore() }
/// ```
///
/// An `ObservableObject` rather than `@Observable` so it works from iOS 15.
@MainActor
public final class NemiSessionModel: ObservableObject {
    public enum State: Equatable, Sendable {
        /// `restore()` has not finished yet.
        case unknown
        case signedOut
        case signedIn(NemiSession)
    }

    @Published public private(set) var state: State = .unknown
    @Published public private(set) var isWorking = false
    /// The last error, other than the person cancelling. Cleared on the next attempt.
    @Published public var lastError: Error?

    public let auth: NemiAuth
    /// An API client that uses `auth` for its tokens.
    public let client: NemiClient
    /// The scopes `signIn()` asks for.
    public var scopes: [NemiScope]

    public init(auth: NemiAuth, scopes: [NemiScope] = NemiScope.defaultSignIn, apiBaseURL: URL = NemiKit.defaultAPIBaseURL) {
        self.auth = auth
        self.scopes = scopes
        self.client = NemiClient(auth: auth, baseURL: apiBaseURL)
    }

    public var session: NemiSession? {
        if case .signedIn(let session) = state { return session }
        return nil
    }

    public var isSignedIn: Bool { session != nil }

    /// Loads the stored session. Call once on launch.
    public func restore() async {
        do {
            if let stored = try await auth.currentSession() {
                state = .signedIn(stored)
            } else {
                state = .signedOut
            }
        } catch {
            lastError = error
            state = .signedOut
        }
    }

    #if canImport(AuthenticationServices) && !os(tvOS) && !os(watchOS)
    /// Shows the Nemi sign-in sheet. Cancelling is not reported as an error.
    public func signIn(presentationAnchor: ASPresentationAnchor? = nil, prefersEphemeralSession: Bool = false) async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let session = try await auth.signIn(
                scopes: scopes,
                presentationAnchor: presentationAnchor,
                prefersEphemeralSession: prefersEphemeralSession
            )
            state = .signedIn(session)
        } catch NemiAuthError.cancelled {
            // The person closed the sheet.
        } catch {
            lastError = error
        }
    }
    #endif

    /// Revokes the session and clears it from the store.
    public func signOut() async {
        isWorking = true
        defer { isWorking = false }
        await auth.signOut()
        state = .signedOut
    }
}
#endif
