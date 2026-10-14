import Foundation
#if canImport(Security)
import Security
#endif

/// Where `NemiAuth` keeps the session between launches.
///
/// `save` must replace the stored session in one step, so a rotated refresh
/// token is never half written.
public protocol NemiTokenStore: Sendable {
    func load() async throws -> NemiSession?
    func save(_ session: NemiSession) async throws
    func clear() async throws
}

/// Keeps the session in memory only. Useful for tests, previews and
/// apps that want people to sign in on every launch.
public actor InMemoryTokenStore: NemiTokenStore {
    private var session: NemiSession?

    public init(session: NemiSession? = nil) { self.session = session }

    public func load() async throws -> NemiSession? { session }
    public func save(_ session: NemiSession) async throws { self.session = session }
    public func clear() async throws { session = nil }
}

#if canImport(Security)
/// Stores the session as one JSON blob in the Keychain
/// (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
///
/// The whole session is one item, so saving a rotated refresh token replaces
/// the old one atomically. The item never leaves the device (no iCloud Keychain sync).
public struct KeychainTokenStore: NemiTokenStore {
    public let service: String
    public let account: String
    public let accessGroup: String?
    /// macOS only: use the data protection keychain (the iOS-style keychain).
    /// Needs a signed app with a Keychain entitlement; set to `false` for
    /// unsigned command line tools. Ignored on other platforms.
    public let useDataProtectionKeychain: Bool

    /// - Parameters:
    ///   - service: the Keychain service. Defaults to `com.nemilab.nemikit`.
    ///   - account: the Keychain account. Use one per client ID if an app has several.
    ///   - accessGroup: a Keychain access group to share the session with app extensions.
    ///   - useDataProtectionKeychain: macOS only, see the property.
    public init(
        service: String = "com.nemilab.nemikit",
        account: String = "session",
        accessGroup: String? = nil,
        useDataProtectionKeychain: Bool = true
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.useDataProtectionKeychain = useDataProtectionKeychain
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        #if os(macOS)
        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        #endif
        return query
    }

    public func load() async throws -> NemiSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            do {
                return try JSONDecoder().decode(NemiSession.self, from: data)
            } catch {
                // An unreadable item (older format, corruption) is treated as signed out.
                try? await clear()
                return nil
            }
        case errSecItemNotFound:
            return nil
        default:
            throw NemiAuthError.storageFailed("SecItemCopyMatching failed (\(status)).")
        }
    }

    public func save(_ session: NemiSession) async throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            throw NemiAuthError.storageFailed("Could not encode the session.")
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var query = baseQuery
            query.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NemiAuthError.storageFailed("SecItemAdd failed (\(addStatus)).")
            }
        default:
            throw NemiAuthError.storageFailed("SecItemUpdate failed (\(updateStatus)).")
        }
    }

    public func clear() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NemiAuthError.storageFailed("SecItemDelete failed (\(status)).")
        }
    }
}
#endif
