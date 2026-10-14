# Changelog

All notable changes to NemiKit are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-14

First release.

### Added

- `NemiAuth`: Sign in with Nemi through `ASWebAuthenticationSession` (iOS, macOS,
  visionOS) with PKCE S256, `state`, `nonce` and RFC 9207 `iss` checks.
  `makeAuthorizationRequest` and `completeAuthorization` for custom flows and
  platforms without a web authentication session (tvOS, watchOS).
- OpenID Connect discovery with a one-day cache, issuer check, and JWKS with
  refetch on an unknown `kid`.
- id_token verification: ES256 (CryptoKit P-256), `iss`, `aud`, `exp`, `iat`,
  `nonce` and `at_hash`.
- `NemiTokenStore` with `KeychainTokenStore` (default) and `InMemoryTokenStore`.
- Automatic, single-flight token refresh with rotated refresh tokens persisted
  before use. `invalid_grant` clears the session.
- `signOut()` revokes the refresh token (RFC 7009) and clears the store.
- `NemiClient` actor for REST API v1, typed against the v1 answers: account,
  workspaces, files (three-step uploads from memory or disk that PUT with the
  server's `headers` and check `max_size`), folders, gallery (paging stream,
  multipart upload, albums with covers, `addPhotos` counts, `setFavorite`
  returning the photo), docs (append mode), sheets (`rows`, `cols`, cells),
  forms (summaries, detail, paged responses), canvas (with optional strokes)
  and calendar (`calendars()`, events with `calendar_id`, `timezone`, `rrule`).
- `NemiAPIError` with `status`, `code`, `message`, `requiredScope` and
  `retryAfter`. 401 refreshes once and retries; 429 retries up to twice,
  honoring `Retry-After`.
- `NemiKitUI`: `SignInWithNemiButton` and `NemiSessionModel`.

[0.1.0]: https://github.com/GuusLab/nemi-swift/releases/tag/0.1.0
