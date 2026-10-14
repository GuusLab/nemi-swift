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
- `NemiClient` actor for REST API v1: account, workspaces, files (including
  three-step uploads from memory or disk), folders, gallery (paging stream and
  multipart upload), docs, sheets, forms, canvas and calendar.
- `NemiAPIError` with `status`, `code`, `message`, `requiredScope` and
  `retryAfter`. 401 refreshes once and retries; 429 retries up to twice,
  honoring `Retry-After`.
- `NemiKitUI`: `SignInWithNemiButton` and `NemiSessionModel`.

### Provisional

The developer platform contract does not yet fix the list envelopes for docs,
sheets, forms, canvas and calendar, or the full shape of forms, form responses
and canvas boards. NemiKit accepts a bare array or an object holding the
expected list, and exposes everything it does not model in a `raw` property.
These types may gain typed fields in a later release.

[0.1.0]: https://github.com/GuusLab/nemi-swift/releases/tag/0.1.0
