# Releasing Mochi

This explains how Mochi gets from source code into something someone can download and run,
written for someone who hasn't done Apple app distribution before. There's no magic here —
just a `.app` folder, a `.dmg` to carry it, and (eventually) Apple's blessing on top of that.

## The short version

- **Building and running Mochi yourself:** nothing here changes — `swift build`, `swift
  test`, `./Scripts/build-app.sh`, `open .build/Mochi.app` all still work exactly as before.
  Everything below is *additional*.
- **Making a `.dmg` someone else can install:** `./Scripts/release.sh`. Works today, with no
  Apple Developer account, and produces an **unsigned** DMG.
- **Publishing that DMG as a GitHub Release:** push a tag like `v1.0.0`. GitHub Actions does
  the rest, automatically.
- **Removing the Gatekeeper warning unsigned builds trigger:** requires joining the Apple
  Developer Program and configuring a few GitHub secrets — see "Apple Developer setup" below.
  Until then, every release is clearly labeled as an unsigned community build, not something
  Apple has vetted.

## Local development

No change from before:

```sh
swift build
swift test
./Scripts/build-app.sh         # assembles .build/Mochi.app (debug)
open .build/Mochi.app
```

## Local unsigned release

```sh
./Scripts/release.sh
```

This:

1. Cleans out `dist/` and the previous `.build/Mochi.app` from any earlier run.
2. Runs `swift test`.
3. Builds Mochi in release configuration and assembles `.build/Mochi.app`.
4. Checks whether Apple Developer signing is configured (see below) — right now, for you, it
   isn't, so it prints a warning and continues anyway: **this is expected, not an error.**
5. Packages `dist/Mochi-<version>.dmg` via `Scripts/package-dmg.sh`.
6. Mounts that DMG, checks `Mochi.app` and the `Applications` shortcut are really inside it,
   and unmounts it again.

You'll see:

```
⚠️  Apple Developer signing is not configured. Creating unsigned DMG.
...
Release ready:
dist/Mochi-0.1.0.dmg
```

That DMG is real and installable — drag `Mochi.app` to `Applications` and it runs like any
other app. The only difference from a "proper" release is that macOS Gatekeeper will show a
warning the first time someone opens it, because Apple hasn't notarized it (see "Gatekeeper
reality" below). That's a normal, expected state for an open-source project without a paid
Apple Developer account yet — not a bug to work around.

### Where the version number comes from

The `VERSION` file at the repo root (currently `0.1.0`) is the single source of truth for
local builds. `Scripts/build-app.sh` reads it and writes the same value into both
`CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist` — Mochi doesn't need two
different version numbers, so it doesn't have two. Set the `MOCHI_VERSION` environment
variable to override it without editing the file (this is how CI makes a release named after
its git tag instead).

## GitHub Release

Pushing a version tag triggers `.github/workflows/release.yml` on a macOS GitHub Actions
runner:

```sh
git tag v1.0.0
git push origin v1.0.0
```

What happens automatically after that:

1. Checks out the repo at that tag and picks an available Xcode.
2. Runs `swift build` and `swift test` — a broken build or a failing test stops here, before
   anything is published.
3. Builds a release `Mochi.app`, with its version taken from the tag (`v1.0.0` → `1.0.0`, so
   the app reports version `1.0.0`, not the `v`-prefixed tag name).
4. Checks whether Apple Developer secrets are configured in this repository (see below).
   - **Not configured (today):** skips signing and notarization, same as a local release.
   - **Configured (once you've completed "Apple Developer setup"):** signs with your
     Developer ID Application identity, notarizes with Apple, and staples the ticket.
5. Packages the DMG, mounts it to verify its contents, and (if signed) verifies the signature
   and Gatekeeper assessment.
6. Uploads the DMG both as a **GitHub Actions artifact** (downloadable from the workflow run
   itself, useful for testing a build before/without cutting a Release) and attaches it to a
   **GitHub Release** named "Mochi v1.0.0", using the tag as the release.

Nothing publishes a release automatically just from a normal commit or PR — only pushing a
tag matching `v*` does. Tagging is a deliberate act you take when you're ready.

## Apple Developer setup

Everything below is **optional and not required for Mochi to work today.** It's only needed
if you want Developer ID–signed, Apple-notarized builds instead of unsigned ones — i.e., no
Gatekeeper warning for people installing Mochi. Signing *outside* the Mac App Store (which is
what Mochi needs, since it isn't sandboxed — see "Why Mochi isn't sandboxed" below) requires
a **Developer ID Application** certificate, which requires Apple Developer Program
membership.

If you've never done any of this before, here's the whole path, step by step:

1. **Join the Apple Developer Program** at [developer.apple.com](https://developer.apple.com)
   (currently $99 USD/year). You'll need an Apple ID and to accept Apple's agreements.

2. **Create a Developer ID Application certificate.** In Xcode: Settings → Accounts → your
   Apple ID → Manage Certificates → the **+** button → "Developer ID Application". (Or via
   [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates)
   directly, if you'd rather not open Xcode.) This certificate — and its private key — lives
   in your Mac's Keychain once created.

3. **Export it as a `.p12` file** for CI to use (GitHub Actions can't reach into your personal
   Keychain): open **Keychain Access**, find the new "Developer ID Application: Your Name
   (TEAMID)" certificate, right-click it, **Export**, choose the `.p12` format, and set a
   password when prompted — you'll need that password again in step 6. Keep this file and its
   password somewhere safe and private; anyone with both can sign software as you.

4. **Find your Team ID.** It's on
   [developer.apple.com/account](https://developer.apple.com/account) under Membership
   details, and it's also the parenthesized code in the certificate's name from step 2/3
   (e.g. `ABCDE12345`).

5. **Set up notarization credentials.** Apple's current, non-deprecated tool for this is
   `notarytool` (never `altool`, which Apple has deprecated). Two authentication options —
   pick one:
   - **App Store Connect API key (recommended by Apple):** at
     [appstoreconnect.apple.com/access/integrations/api](https://appstoreconnect.apple.com/access/integrations/api),
     create a key with at least the "Developer" role. You get three things: a `.p8` private
     key file (downloadable once, so save it immediately), a **Key ID**, and an **Issuer ID**.
   - **Apple ID + app-specific password:** generate an app-specific password at
     [appleid.apple.com](https://appleid.apple.com) (Sign-In and Security → App-Specific
     Passwords) for your Apple ID. Simpler to set up, slightly less robust than an API key.

6. **Add these as GitHub repository Secrets** (repo → Settings → Secrets and variables →
   Actions → "New repository secret"). Exact names and what goes in each:

   | Secret | What it is |
   |---|---|
   | `APPLE_CERTIFICATE_BASE64` | The `.p12` from step 3, base64-encoded: `base64 -i YourCert.p12 \| pbcopy`, then paste. |
   | `APPLE_CERTIFICATE_PASSWORD` | The password you set when exporting that `.p12` in step 3. |
   | `APPLE_SIGNING_IDENTITY` | The certificate's exact name, e.g. `Developer ID Application: Your Name (ABCDE12345)` — `security find-identity -v -p codesigning` lists it exactly as Keychain Access shows it. |
   | `APPLE_TEAM_ID` | Your Team ID from step 4, e.g. `ABCDE12345`. |

   Then, for notarization, **either** (API key — recommended):

   | Secret | What it is |
   |---|---|
   | `APPLE_NOTARIZATION_KEY_ID` | The Key ID from step 5. |
   | `APPLE_NOTARIZATION_ISSUER_ID` | The Issuer ID from step 5. |
   | `APPLE_NOTARIZATION_KEY_PATH` | *(Not a secret value — see note below.)* |

   **or** (Apple ID + app-specific password):

   | Secret | What it is |
   |---|---|
   | `APPLE_NOTARIZATION_APPLE_ID` | The Apple ID email you enrolled with. |
   | `APPLE_NOTARIZATION_PASSWORD` | The app-specific password from step 5. |

   > **Note on the API key file itself:** `APPLE_NOTARIZATION_KEY_PATH` needs to point
   > `notarytool` at the actual `.p8` file, which means the file has to exist on the runner's
   > disk at submission time — it can't just be a plain secret string. The straightforward way
   > to wire this up once you're actually doing API-key notarization: add one more secret
   > (e.g. `APPLE_NOTARIZATION_KEY_BASE64`, the `.p8` file base64-encoded, the same way as step
   > 6's certificate), add a "write it to a temp file" step to `.github/workflows/release.yml`
   > right before the "Notarize app" step, and set `APPLE_NOTARIZATION_KEY_PATH` to that file's
   > path in the `env:` for that step. This repo ships the Apple-ID/app-specific-password path
   > as the simpler default to get started with; switch to the API key once the basic flow is
   > proven out, if you'd rather.

7. **Run a release**: `git tag v1.0.0 && git push origin v1.0.0`. Watch the Actions tab — the
   "Determine signing mode" step will now say Mode B (signed + notarized) instead of Mode A.

8. **Verify the result** once it's published: download the DMG from the Release, and check

   ```sh
   codesign --verify --deep --strict --verbose=2 /Applications/Mochi.app
   spctl --assess --type execute --verbose=2 /Applications/Mochi.app
   xcrun stapler validate /Applications/Mochi.app
   ```

   A signed, notarized, stapled build passes all three with no Gatekeeper warning on launch.

### Why Mochi isn't sandboxed

Mochi launches local tools via `Process` (`/usr/bin/open`, `/usr/bin/git`, your preferred
terminal, your own `openclaw` CLI if it's installed) and reads whatever project paths an agent
reports. The App Sandbox — required for the Mac App Store, optional for Developer ID
distribution — would block or require interactive, per-file user approval for nearly all of
that, breaking the actual integration Mochi exists to provide. Developer ID distribution
(what this whole document is about) doesn't require sandboxing, only code signing +
notarization, so this is a deliberate, documented choice, not an oversight — see
`Resources/Mochi.entitlements`.

Mochi does run with **Hardened Runtime** enabled (`codesign --options runtime` in
`Scripts/sign-app.sh`), which notarization *does* require — but Hardened Runtime doesn't
restrict launching other processes or reading the filesystem the way sandboxing does. It
mainly hardens against: run-time code injection, unsigned executable memory, and a handful of
other Mach/debugging-level attack surfaces. Mochi needs none of the exceptions you'd otherwise
have to carve back out for things like JIT compilation or disabled library validation.

## Gatekeeper reality

Until Developer ID signing + notarization are configured (see above), every Mochi release is
**unsigned**. When someone downloads and opens it, macOS Gatekeeper will say something like
*"Mochi can't be opened because it is from an unidentified developer"* or similar. This is
expected, documented behavior for any unsigned app — not a Mochi bug, and the release notes
for every unsigned build say so explicitly.

The workaround for a user hitting this, until a signed build exists: right-click (Control-
click) `Mochi.app` in Finder and choose **Open**, then confirm in the dialog that appears —
this is the standard, Apple-documented way to run a specific app you've chosen to trust once,
and it only has to be done the first time. Mochi's own code never tells macOS to bypass or
disable Gatekeeper, and never will — that's a decision for the person running their own Mac,
made through Apple's own UI, not something an app should automate around.

Once Developer ID + notarization are configured and producing green "Mode B" releases, those
signed/notarized builds become the preferred public release artifact, and the release notes
stop mentioning Gatekeeper at all, because there's nothing left to warn about.

## Release checks

Every release, signed or not, runs through:

- `Mochi.app` exists and contains a real, executable `Mochi` binary.
- The DMG actually mounts.
- `Mochi.app` and the `Applications` symlink both exist inside the mounted volume.

A signed build additionally runs:

- `codesign --verify --deep --strict` on the packaged app.
- `spctl --assess --type execute` (Gatekeeper's own opinion).
- `xcrun stapler validate` (confirms the notarization ticket is actually stapled on, not just
  that notarization succeeded at submission time).

Any of these failing stops the release before a GitHub Release is published — nothing is ever
uploaded on a wing and a prayer.

## Security notes

- No certificate, private key, password, or Apple credential of any kind lives in this
  repository — only in GitHub Actions Secrets, which GitHub encrypts and which this workflow
  never prints to its own logs.
- The temporary keychain `Scripts/ci-import-certificate.sh` creates during CI
  (`Scripts/ci-cleanup-keychain.sh` removes it again, even if an earlier step failed) exists
  for exactly one workflow run, on a disposable GitHub-hosted runner that's destroyed
  afterward regardless.
- The release workflow's GitHub token permissions are limited to `contents: write` — just
  enough to publish a Release — nothing else.

## Don't publish a fake release

Nothing in this repository creates a `v1.0.0` tag automatically, and nothing here should be
read as a claim that Mochi *is* production-ready or Apple-verified software. Tagging and
pushing a release is a deliberate, manual act for whoever maintains this repo — not something
that happens as a side effect of normal development.
