import CryptoKit
import Foundation
#if canImport(Security)
import Security
#endif

/// A PKCE (RFC 7636) verifier and its S256 challenge.
public struct PKCE: Sendable, Equatable {
    /// The secret kept by the app and sent to the token endpoint.
    public let verifier: String
    /// `base64url(sha256(verifier))`, sent to the authorize endpoint.
    public let challenge: String
    /// Always `S256`.
    public let method: String = "S256"

    /// Creates a pair from a fresh 32-byte random verifier (43 characters).
    public init() throws {
        try self.init(verifier: Base64URL.encode(SecureRandom.bytes(count: 32)))
    }

    /// Creates a pair from an existing verifier (43 to 128 unreserved characters).
    public init(verifier: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard (43...128).contains(verifier.count),
              verifier.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw NemiAuthError.invalidConfiguration("A PKCE verifier must be 43 to 128 unreserved characters.")
        }
        self.verifier = verifier
        self.challenge = PKCE.challenge(for: verifier)
    }

    /// `base64url(sha256(verifier))` without padding.
    public static func challenge(for verifier: String) -> String {
        Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

enum SecureRandom {
    static func bytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        #if canImport(Security)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw NemiAuthError.invalidConfiguration("The system random number generator failed (\(status)).")
        }
        #else
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max, using: &generator) }
        #endif
        return Data(bytes)
    }

    /// A URL-safe random string with `count` bytes of entropy.
    static func token(count: Int = 32) throws -> String {
        Base64URL.encode(try bytes(count: count))
    }
}
