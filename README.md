# NemiKit

Sign in with Nemi and the Nemi REST API for Swift. Native, async/await, strict
concurrency, zero dependencies.

| Product | What it gives you |
| --- | --- |
| `NemiKit` | `NemiAuth` (OAuth 2.0 + OpenID Connect with PKCE), Keychain token storage, automatic refresh, and `NemiClient` for the REST API. No UI dependencies. |
| `NemiKitUI` | SwiftUI `SignInWithNemiButton` and the `NemiSessionModel` observable object. |

Platforms: iOS 15, macOS 12, visionOS 1, tvOS 15, watchOS 8. The sign-in sheet
(`ASWebAuthenticationSession`) is available on iOS, macOS and visionOS. On tvOS
and watchOS the API client and token handling work, and you can drive sign-in
yourself with `makeAuthorizationRequest` and `completeAuthorization`.

## Install

In Xcode, choose File, Add Package Dependencies, and enter
`https://github.com/GuusLab/nemi-swift`. Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/GuusLab/nemi-swift", from: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "NemiKit", package: "nemi-swift"),
        .product(name: "NemiKitUI", package: "nemi-swift"), // optional
    ]),
]
```

## Register your app

1. Apply as a developer at [dev.nemilab.com](https://dev.nemilab.com). An admin approves the account.
2. Create a **public** app (native apps never hold a client secret; PKCE protects the flow).
3. Add a redirect URI. Redirect URIs are exact-match. Pick one of:
   - **A private-use scheme** built from a domain you control, for example
     `com.example.app:/callback`. Simplest, works on every OS version.
   - **An https universal link**, for example `https://example.com/nemi/callback`.
     Needs an Associated Domains entitlement (`webcredentials:example.com`) and an
     `apple-app-site-association` file on that domain. NemiKit catches https
     callbacks with `ASWebAuthenticationSession.Callback.https` on iOS 17.4,
     macOS 14.4 and visionOS 1.1 or later.
4. Tick the scopes the app may ask for, and copy the `nemi_app_...` client ID.

While the app is in `development`, only you and up to 25 test users can sign in.

### Do I need URL types in Info.plist?

No. `ASWebAuthenticationSession` watches for the callback scheme itself and
hands the URL straight back to NemiKit; the redirect never goes through
`application(_:open:)` or `onOpenURL`. Registering the scheme under
`CFBundleURLTypes` is only needed if some other part of your app has to open
those URLs, and leaving it out means no other app can claim them through you.

## SwiftUI quick start

```swift
import NemiKit
import NemiKitUI
import SwiftUI

let auth = NemiAuth(
    clientId: "nemi_app_xxxxxxxxxxxxxxxxxxxxxxxx",
    redirectURI: URL(string: "com.example.app:/callback")!
)

@main
struct MyApp: App {
    @StateObject private var model = NemiSessionModel(
        auth: auth,
        scopes: [.openid, .profile, .email, .offlineAccess, .filesRead]
    )

    var body: some Scene {
        WindowGroup {
            Group {
                if model.isSignedIn {
                    HomeView(client: model.client)
                } else {
                    SignInWithNemiButton {
                        Task { await model.signIn() }
                    }
                    .disabled(model.isWorking)
                    .padding()
                }
            }
            .task { await model.restore() }
        }
    }
}

struct HomeView: View {
    let client: NemiClient
    @State private var name = ""

    var body: some View {
        Text("Hello, \(name)")
            .task { name = (try? await client.me().name) ?? "" }
    }
}
```

`SignInWithNemiButton` is a black capsule by default. Use `style: .white` on dark
backgrounds, or `.automatic` to follow the color scheme. The label reads
"Sign in with Nemi" (or `.continueWith`, `.signUp`) and VoiceOver reads the same.

## UIKit quick start

```swift
import NemiKit
import UIKit

final class SignInViewController: UIViewController {
    let auth = NemiAuth(
        clientId: "nemi_app_xxxxxxxxxxxxxxxxxxxxxxxx",
        redirectURI: URL(string: "com.example.app:/callback")!
    )
    lazy var client = NemiClient(auth: auth)

    @objc func signInTapped() {
        Task { @MainActor in
            do {
                let session = try await auth.signIn(
                    scopes: [.openid, .profile, .email, .offlineAccess, .filesRead],
                    presentationAnchor: view.window
                )
                print("Signed in as", session.user?.name ?? session.user?.sub ?? "?")
                let workspaces = try await client.workspaces()
                print(workspaces.map(\.name))
            } catch NemiAuthError.cancelled {
                // The person closed the sheet.
            } catch {
                present(UIAlertController(title: "Sign in failed", message: error.localizedDescription, preferredStyle: .alert), animated: true)
            }
        }
    }

    @objc func signOutTapped() {
        Task { await auth.signOut() }
    }
}
```

On the next launch, `try await auth.currentSession()` returns the stored session
(or `nil`). You never have to refresh by hand: `NemiClient` asks `NemiAuth` for
a token before each call, and `NemiAuth` refreshes when the token expires within
a minute.

## Gallery example

```swift
let client = NemiClient(auth: auth)   // needs gallery.read / gallery.write
let workspace = try await client.workspaces().first!

// One page at a time (photo.color is a #rrggbb placeholder while thumbnails load)
let page = try await client.gallery.photos(workspaceId: workspace.id, limit: 50)
print(page.photos.count, "photos, next cursor:", page.nextCursor ?? "none")

// Or every photo, newest first, paging behind the scenes
for try await photo in client.gallery.allPhotos(workspaceId: workspace.id) {
    print(photo.name ?? photo.id, photo.width, "x", photo.height)
    if photo.favorite { break }
}

// Full-size URL and the albums it is in (URL valid 15 minutes: fetch again rather than storing it)
let full = try await client.gallery.photo(id: page.photos[0].id)
print(full.albums?.map(\.name) ?? [])
let (imageData, _) = try await URLSession.shared.data(from: full.url!)

// Upload (JPEG, PNG, HEIC, WebP, AVIF up to 50 MB)
let uploaded = try await client.gallery.upload(imageData: imageData, fileName: "copy.jpg", workspaceId: workspace.id)
let album = try await client.gallery.createAlbum(name: "Favourites", workspaceId: workspace.id)
let result = try await client.gallery.addPhotos([uploaded.id], toAlbum: album.id)
print("added", result.added, "skipped", result.skipped)
try await client.gallery.setFavorite(true, photoId: uploaded.id)
```

## API overview

| Call | Scope |
| --- | --- |
| `client.me()`, `client.workspaces()` | any |
| `files.list`, `files.search`, `files.get`, `files.downloadURL` | `files.read` |
| `files.upload(data:...)`, `files.upload(fileURL:...)`, `files.update`, `files.delete`, `folders.create` | `files.write` |
| `gallery.photos`, `gallery.allPhotos`, `gallery.photo`, `gallery.albums` | `gallery.read` |
| `gallery.upload`, `gallery.createAlbum`, `gallery.addPhotos`, `gallery.setFavorite` | `gallery.write` |
| `docs.list/get` and `docs.create/update(mode:)/delete` | `docs.read` / `docs.write` |
| `sheets.list/get` and `sheets.create(cells:)/updateCells/delete` | `sheets.read` / `sheets.write` |
| `forms.list/get/responses(limit:offset:)` and `forms.create/delete` | `forms.read` / `forms.write` |
| `canvas.list`, `canvas.get(includeStrokes:)` | `canvas.read` |
| `calendar.calendars` | `calendar.read` or `calendar.write` |
| `calendar.events(calendarId:)` and `calendar.create/update/delete` | `calendar.read` / `calendar.write` |

Without a `workspaceId`, lists span every workspace the person can read and
creates go to the first workspace they can write in. A new event without a
`calendarId` lands in the person's primary Nemi calendar.

File uploads run in three steps: NemiKit creates the upload, PUTs the bytes to
the presigned URL with exactly the headers the server returned (and never your
access token), then completes it. Files can be at most 50 MB; NemiKit also
checks the upload's `max_size` before sending.

Form responses come back as records keyed by the response sheet's column
headers (`response["Your name"]`), newest first, with `total` for paging.
Forms and canvas boards also keep everything the server sent in `raw`.

### Errors

API calls throw `NemiAPIError`:

```swift
do {
    _ = try await client.files.list(workspaceId: id)
} catch let error as NemiAPIError where error.code == .insufficientScope {
    // error.requiredScope == .filesRead: sign in again asking for it.
}
```

A 401 triggers one refresh and one retry. A 429 is retried up to twice, waiting
for `Retry-After`. Sign-in and refresh throw `NemiAuthError`; `.cancelled` means
the person closed the sheet, `.sessionExpired` means the refresh token was
rejected and the stored session was cleared.

## Security notes

- PKCE S256, `state`, `nonce` and the RFC 9207 `iss` parameter are checked on every sign-in.
- id_tokens are verified with CryptoKit (ES256 against the issuer's JWKS): signature, `iss`, `aud`, `exp` and `nonce`.
- Sessions live in the Keychain as one item, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synced.
  On macOS the data protection keychain is used; pass `KeychainTokenStore(useDataProtectionKeychain: false)`
  for unsigned command line tools.
- Refresh tokens rotate on every use. NemiKit refreshes once even when many requests need a token at the
  same moment, and saves the new refresh token before using it, because presenting a spent refresh token
  revokes the whole session.
- Presigned upload and download URLs never receive the bearer token.

## Development

```bash
swift build
swift test
```

## License

MIT. See [LICENSE](LICENSE).
