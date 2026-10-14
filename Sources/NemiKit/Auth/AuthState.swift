import Foundation

/// Mutable auth state behind one actor: the cached session, discovery, JWKS,
/// and the single in-flight refresh.
///
/// Actor methods can interleave at every `await`, so every check that decides
/// to start a refresh happens with no `await` between the check and storing
/// the new task. That is what makes the refresh single-flight.
actor AuthState {
    private let store: any NemiTokenStore
    private var loaded = false
    private var current: NemiSession?
    private var refreshTask: Task<NemiSession, Error>?
    /// Bumped on sign-in and sign-out so a refresh that finishes late cannot resurrect an old session.
    private var generation = 0

    private var discovery: (document: NemiDiscoveryDocument, fetchedAt: Date)?
    private var keys: (keys: [NemiJWK], fetchedAt: Date)?
    private let discoveryTTL: TimeInterval = 24 * 60 * 60

    init(store: any NemiTokenStore) {
        self.store = store
    }

    // MARK: Caches

    func cachedDiscovery(now: Date) -> NemiDiscoveryDocument? {
        guard let discovery, now.timeIntervalSince(discovery.fetchedAt) < discoveryTTL else { return nil }
        return discovery.document
    }

    func storeDiscovery(_ document: NemiDiscoveryDocument, now: Date) {
        discovery = (document, now)
    }

    func cachedKeys(now: Date) -> [NemiJWK]? {
        guard let keys, now.timeIntervalSince(keys.fetchedAt) < discoveryTTL else { return nil }
        return keys.keys
    }

    func storeKeys(_ keys: [NemiJWK], now: Date) {
        self.keys = (keys, now)
    }

    // MARK: Session

    func session() async throws -> NemiSession? {
        try await loadIfNeeded()
        return current
    }

    func replace(with session: NemiSession) async throws {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        try await store.save(session)
        current = session
        loaded = true
    }

    func cancelRefreshAndClear() {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        current = nil
        loaded = true
    }

    func validSession(
        now: @Sendable () -> Date,
        refresh: @escaping @Sendable (NemiSession) async throws -> NemiSession
    ) async throws -> NemiSession {
        try await loadIfNeeded()
        if let refreshTask { return try await refreshTask.value }
        guard let session = current else { throw NemiAuthError.notSignedIn }
        if !session.isExpired(at: now()) { return session }
        return try await startRefresh(from: session, refresh: refresh)
    }

    /// Refreshes unless somebody else already replaced `rejectedAccessToken`.
    func forceRefresh(
        rejectedAccessToken: String?,
        refresh: @escaping @Sendable (NemiSession) async throws -> NemiSession
    ) async throws -> NemiSession {
        try await loadIfNeeded()
        if let refreshTask { return try await refreshTask.value }
        guard let session = current else { throw NemiAuthError.notSignedIn }
        if let rejectedAccessToken, session.accessToken != rejectedAccessToken {
            return session
        }
        return try await startRefresh(from: session, refresh: refresh)
    }

    private func startRefresh(
        from session: NemiSession,
        refresh: @escaping @Sendable (NemiSession) async throws -> NemiSession
    ) async throws -> NemiSession {
        // No `await` between the caller's check and this assignment.
        if let refreshTask { return try await refreshTask.value }
        let startedGeneration = generation
        let task = Task<NemiSession, Error> {
            let fresh = try await refresh(session)
            try await self.commitRefresh(fresh, generation: startedGeneration)
            return fresh
        }
        refreshTask = task
        do {
            let fresh = try await task.value
            if generation == startedGeneration { refreshTask = nil }
            return fresh
        } catch {
            if generation == startedGeneration {
                refreshTask = nil
                if case NemiAuthError.sessionExpired = error {
                    current = nil
                    try? await store.clear()
                }
            }
            throw error
        }
    }

    /// Persists the rotated tokens before anyone can use them, so a crash
    /// never leaves the store holding a refresh token that was already spent.
    private func commitRefresh(_ fresh: NemiSession, generation startedGeneration: Int) async throws {
        guard generation == startedGeneration else { throw CancellationError() }
        try await store.save(fresh)
        guard generation == startedGeneration else {
            // Signed out or signed in again while saving: put the newer state back.
            if let current { try? await store.save(current) } else { try? await store.clear() }
            throw CancellationError()
        }
        current = fresh
    }

    private func loadIfNeeded() async throws {
        guard !loaded else { return }
        let stored = try await store.load()
        // Another call may have loaded or signed in while we were waiting.
        if !loaded {
            current = stored
            loaded = true
        }
    }
}
