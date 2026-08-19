# Releasing to the App Store

The runbook for putting Cirrhy on the iOS App Store. Everything here is
specific to this repository; the generic parts of Apple's process are left to
Apple's own documentation.

**Cirrhy is published under a third party's Apple Developer Program team**
(Appific), by arrangement with the author. That is the unusual part of this
setup and the source of most of the friction below, so it is called out
wherever it changes a step.

CI deliberately does not build iOS — `.github/workflows/release.yml` has jobs
for the other four targets and none for this one, because an installable iOS
build needs a signing identity that CI should not hold. Every App Store upload
therefore happens from a Mac, by hand.

## One-time setup

### 1. Get the publishing team onto this Mac

Xcode → Settings → Accounts → **+** → Apple ID, signed in with **the Apple ID
that received the team invitation**. The team then appears in that account's
team list, along with its ten-character team ID.

`tool/ios-signing.sh` reads certificates from the keychain and provisioning
profiles from disk, so it stays blind to the team until Xcode has minted one of
those. Force that:

```sh
open app/ios/Runner.xcworkspace
```

Runner target → Signing & Capabilities → Team → the publishing team. Xcode
creates the development certificate on the spot. After that:

```sh
tool/ios-signing.sh                 # the team should now be listed
tool/ios-signing.sh <TEAM-ID>       # point the build at it
```

That writes `app/ios/Flutter/Signing.xcconfig`, which is gitignored — which
Apple ID signs a build is a property of the machine, not of the project.

### 2. Confirm the role

Ask the team's admin which role you were given. It decides whether you can
finish at all:

- **Developer** — can upload builds to TestFlight, but cannot create the app
  record or submit for review. You would be blocked at step 4.
- **App Manager** — can do everything needed here, including using the team's
  cloud-managed distribution certificate, which is what actually signs the
  store build.

Ask for **App Manager**. "No distribution certificate available" during export
is this, showing up late.

### 3. Settle three things with the publisher, in writing

Publishing under someone else's team is mostly a paperwork question. These are
the ones that are expensive to revisit:

1. **The bundle ID is `com.lorands.cirrhyapp`, and stays in the author's
   reverse domain.** Apple does not verify domain ownership for App IDs, so
   the publisher's team can register it, and there is a concrete reason to
   prefer it over a publisher-domain one: an App Transfer — the mechanism for
   moving the app to another account later — carries the bundle ID with it, so
   the author's domain keeps the identity coherent through such a move.

   The `app` suffix is scar tissue: the plain `com.lorands.cirrhy` had already
   been registered to the author's **free personal team** by Xcode, silently,
   on the first iPhone device build. App IDs are globally unique across every
   team, so the publishing team could not register it, and a free personal team
   has no developer-portal access from which to delete it. iOS and macOS both
   moved, so the two Apple platforms can still share one record as a Universal
   Purchase; Android and Linux kept `com.lorands.cirrhy`, and so did the method
   channel names. DESIGN.md §7 carries the reasoning.

   > **Do not build a not-yet-registered bundle ID under a free personal
   > team.** That is what burned the first one. Register the App ID under the
   > publishing team *before* the first device build on a new identifier.
2. **The listing's seller name will be the publisher's**, and the App Store
   Connect app record belongs to their account. Agree up front what happens if
   the arrangement ends: App Transfer is the mechanism, and it requires the
   receiving account to be a paid Developer Program member.
3. **Who hosts the privacy policy and support URLs.** Both are mandatory. This
   repository is public and carries both
   ([privacy](../legal/privacy-policy.md), [support](../legal/support.md)),
   which is the default; the publisher may prefer them on their own domain, in
   which case those pages move and this repo keeps the canonical text.

### 4. Repo changes

Two keys in `app/ios/Runner/Info.plist`:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

Without it every upload parks in "Missing Compliance" until the question is
answered by hand in App Store Connect. `false` is accurate: the app makes no
network connections, and the SHA-256 it uses to detect document changes is
hashing, not encryption.

```xml
<key>CFBundleLocalizations</key>
<array>
  <string>en</string><string>hu</string><string>es</string>
  <string>it</string><string>de</string>
</array>
```

gen-l10n produces no `.lproj` folders, so without this the store page
advertises English only despite the app shipping five languages. **This is a
second place to update when a sixth language lands**, alongside the `shipped`
set in `app/test/l10n_test.dart` — the only such place, and the reason it is
worth writing down.

Optionally add an app-level `PrivacyInfo.xcprivacy`. It is not strictly
required — the Flutter engine ships a manifest covering the file-timestamp and
boot-time APIs, and `shared_preferences_foundation`, `path_provider_foundation`
and `file_selector_ios` each ship their own — but it is cheap insurance against
an ITMS-91053 warning mail after upload.

One decision to make consciously: `TARGETED_DEVICE_FAMILY` is `"1,2"`, so iPad
is included. That means Apple requires iPad 13" screenshots and reviews the
iPad experience. The adaptive shell handles iPad properly (the 220px rail above
900px), so keeping it is the right call — it is just extra screenshot work.

### 5. Create the app record

App Store Connect → My Apps → **+** → New App, under the publishing team.

Platform iOS; name `Cirrhy` (checked for availability at creation, and reserved
from then on); primary language; bundle ID `com.lorands.cirrhyapp`; SKU `cirrhy`;
user access Full Access.

The SKU carries **no platform suffix on purpose**. It is internal, permanent,
and unique only within the publisher's account — and because iOS and macOS
share the bundle ID `com.lorands.cirrhyapp`, a future Mac App Store version can
join this same app record as a Universal Purchase, which shares the one SKU.
`cirrhy-ios` would be wrong from that day on. Check the publisher's own SKU
convention before submitting the form, since it appears in their financial
reports.

If the bundle ID is not in the dropdown, register it first at
developer.apple.com → Certificates, Identifiers & Profiles → Identifiers →
**+** → App IDs.

Then fill the listing from [`app-store-listing.md`](app-store-listing.md),
which holds every field's copy ready to paste, including the App Review notes —
which matter here more than usual, because Cirrhy gates the whole app behind
picking a folder and a reviewer who does not expect that reads it as a broken
app.

## Each release

### Build

For the first attempt, or any time you want a build without cutting a release,
build directly — `tool/release.sh` tags and pushes before it builds, which is
not what you want while still proving the signing works:

```sh
cd app && flutter build ipa --release
```

Once that succeeds, the normal path is the release script, which bumps
`pubspec.yaml` (including the `+N` build number, which Apple requires to
increase on **every** upload), bumps the About screen's `appVersion`, tags,
pushes, and then prepares the store packages:

```sh
tool/release.sh <version>           # → dist/cirrhy-<version>-appstore.ipa
```

The `.ipa` step is skipped on a non-macOS host and when no signing team is
configured, and says so rather than failing silently.

### Upload

**Transporter.app** (free, Mac App Store) — drag the `.ipa` in. Xcode's
Organizer → Distribute App does the same job if you built through Xcode.

### TestFlight first

Add yourself as an internal tester and install from TestFlight before touching
metadata. Internal TestFlight needs no review, so it proves signing, upload and
install on a real device while mistakes are still cheap to fix.

### Submit

Attach the build to the version, confirm export compliance is not being asked
(step 4), and submit. First review typically takes a day or two.

## Other stores

- **Mac App Store** is a separate submission of the same app record family. The
  macOS target already runs under App Sandbox with the entitlements in
  `app/macos/Runner/*.entitlements`, so it is closer than it looks — that
  sandbox is why macOS uses a security-scoped bookmark like iOS rather than a
  plain path (DESIGN.md §4).
- **Play Store**: `tool/release.sh` already prepares
  `dist/cirrhy-<version>-playstore.aab`, but it is debug-signed until an upload
  keystore exists, and the Play Console will refuse it as-is.
