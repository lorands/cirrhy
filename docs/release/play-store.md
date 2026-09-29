# Releasing to the Play Store

The runbook for putting Cirrhy on Google Play. Everything here is specific to
this repository; the generic parts of Google's process are left to Google's own
documentation.

**Cirrhy is published under a third party's Play Console developer account**
(Appific), by arrangement with the author — the same arrangement that puts it
on the App Store, and the same source of most of the friction below, so it is
called out wherever it changes a step.
[`app-store.md`](app-store.md) is the sibling of this document; where the two
stores differ in a way that matters, this one says so rather than assuming you
have both open.

CI deliberately does not build a publishable Android artifact.
`.github/workflows/release.yml` produces a **debug-signed APK** for the GitHub
Releases page, which is installable and honest about what it is; the Play
Console refuses it. A publishable bundle needs the upload key, and CI should
not hold that any more than it should hold an Apple signing identity. Every
Play upload therefore happens from a developer machine, by hand.

## One-time setup

### 1. Get access to the publishing account

Ask the account's owner to invite you at **Users and permissions**, and to
grant, at minimum:

- **Account-level:** *Create, edit, and delete draft apps* — without it you
  cannot create the app record at step 6, and you will not find that out until
  you look for a button that is not there.
- **App-level, once the record exists:** *Release manager*, which bundles
  releasing to testing tracks and production, managing the store listing, and
  viewing App signing. *Release to production* is the one people forget to
  include; without it you can upload all day and never ship.

The Play Console's permission model is per-app once an app exists, so it is
normal for the second half of this to be granted after step 6 rather than
before it.

### 2. Confirm the account is an organization account

This is worth thirty seconds and can cost fourteen days.

Google requires **personal** developer accounts created after 13 November 2023
to run a closed test with **at least 12 testers, opted in continuously for 14
days**, before they may apply for production access. Since April 2026 Google
also rejects applications where the testers demonstrably did not use the app.
**Organization accounts are exempt.** Appific Kft. is a registered company, so
the exemption applies and Cirrhy can go straight to production — but confirm it
in the Console (**Account details → Account type**) rather than inferring it
from the name, because being wrong about this changes the release plan from
"submit on Tuesday" to "find twelve people and wait a fortnight".

If Cirrhy ever moves to the author's own personal account, that requirement
comes with it. Plan the closed test first in that case, not after.

### 3. Settle three things with the publisher, in writing

Publishing under someone else's account is mostly a paperwork question. These
are the ones that are expensive to revisit:

1. **The application ID is `com.lorands.cirrhy`, and it is permanent.** More
   permanent than Apple's: on Play the applicationId *is* the app's identity,
   and after the first upload it can never be changed. A different one later
   is a different app — no users, no reviews, no install base, and no upgrade
   path for anyone who already has it. `app/test/android_manifest_test.dart`
   pins it so a rename fails the suite rather than the store.

   Note this is the *plain* reverse domain, not the `com.lorands.cirrhyapp`
   the Apple platforms carry. That divergence is scar tissue from a burned App
   ID, and it is deliberate — DESIGN.md §7. Do not "fix" it.
2. **The listing's developer name will be the publisher's**, and the app
   record belongs to their account. Agree up front what happens if the
   arrangement ends: Google supports transferring an app between developer
   accounts, and it keeps the applicationId, install base and reviews intact,
   but it needs both accounts in good standing and the receiving account's
   merchant/transaction details. It is a form, not a favour, but it is not
   instant either.
3. **Who hosts the privacy policy and support URLs.** The privacy policy URL
   is mandatory and Play checks that it resolves. This repository is public and
   carries both ([privacy](../legal/privacy-policy.md),
   [support](../legal/support.md)), which is the default; the publisher may
   prefer them on their own domain, in which case those pages move and this
   repo keeps the canonical text.

### 4. Create the upload key

```sh
tool/android-signing.sh --create     # → ~/.cirrhy/upload-keystore.jks
tool/android-signing.sh              # shows the certificate fingerprints
```

That writes `app/android/key.properties`, which is gitignored — which key signs
a build is a property of the machine, not of the project, exactly as
`ios/Flutter/Signing.xcconfig` is on the Apple side. Without it a `--release`
build falls back to debug keys, so a fresh clone still builds; it just cannot
publish what it builds, and the build scripts say so rather than letting you
find out at the Console.

**Back up the keystore and `key.properties` together** — the passwords live in
the second file, not the first — somewhere that survives this machine.

The reassuring half, worth knowing before the anxiety sets in: under **Play App
Signing**, which is mandatory for new apps, Google holds the *app signing key*
that devices verify and it never leaves their infrastructure. What this script
makes is the *upload key*, which only proves an upload came from you. Lose it
and you request an upload key reset in the Console; Google registers a new
certificate in a couple of days. Lose the app signing key and the app would be
unrecoverable — but you never had it to lose. Back up anyway: a reset costs
days you would rather not spend mid-release.

### 5. Repo changes

**None.** That is not an oversight, and it is the cheerful difference from the
App Store, which needed two `Info.plist` keys before it would behave. Worth
recording *why*, since each absence looks like something forgotten:

- **No language declaration.** iOS needed `CFBundleLocalizations` because
  gen-l10n produces no `.lproj` folders and the store page would otherwise
  advertise English alone. Play does not read languages from the bundle at
  all — the listing's language list is exactly the set of **store listing
  translations** you add in the Console. So a sixth language costs a listing
  translation here, and nothing in the repo. See
  [`play-store-listing.md`](play-store-listing.md).
- **No `android:localeConfig`.** It would put the app in Android 13+'s
  per-app language menu, which sounds free until you notice it is an XML file
  enumerating the shipped languages — a second place to update per language,
  which is precisely what CLAUDE.md's "adding a language must never mean
  touching code" rule exists to prevent. The app has its own picker on the
  preferences screen, which works on every supported version rather than only
  the last few. Considered, declined.
- **No export-compliance key.** Apple asks per upload until
  `ITSAppUsesNonExemptEncryption` answers it. Play asks once, in the App
  content section, and the answer is in
  [`play-store-listing.md`](play-store-listing.md).
- **Target API level is already current.** `flutter.targetSdkVersion` is 36,
  and Play's floor for new apps and updates is below that. It rises with the
  Flutter SDK rather than by hand, which is the intended mechanism; the day
  Play's floor overtakes the pinned Flutter version, upgrading Flutter is the
  fix, not editing the Gradle file.

The one thing to *check* rather than change is the permission set. The shipping
manifest requests two permissions and, deliberately, not `INTERNET` — the
release build cannot open a socket, which is what makes the Data safety
declaration a fact about the binary rather than a promise about the source.
`app/test/android_manifest_test.dart` asserts it on every run.

### 6. Create the app record

Play Console → **All apps → Create app**, under the publishing account.

App name `Cirrhy`; default language English (United States); this is an **app**,
not a game; and **Free**, which is worth pausing on: a free app can never be
switched to paid afterwards. Free is right for Cirrhy and it is not reversible.

Then work through the tasks the Console lists, filling every field from
[`play-store-listing.md`](play-store-listing.md), which holds the copy ready to
paste alongside the Data safety and content-rating answers. Two of them have
teeth:

- **Data safety** is a declaration Google holds the publisher to, not
  marketing copy. Cirrhy's is the easy case — nothing collected, nothing
  shared — but answer it from the listing document rather than from memory.
- **App access.** Declare that all functionality is available without special
  access; it is true, since Cirrhy has no accounts of any kind. But note that
  Play offers no reviewer-notes field equivalent to Apple's, and Cirrhy gates
  the entire app behind picking a folder. On the App Store that gate needed a
  paragraph of explanation to avoid a Guideline 2.1 rejection; here there is
  nowhere to put that paragraph, so the first-run screen's own clarity is the
  only thing standing between a reviewer and "the app does nothing". If a
  rejection does mention it, the appeal text is in the listing document.

Screenshots are generated rather than taken by hand, for the same reason the
app icons are:

```sh
tool/gen_screenshots.sh --android         # phone and tablet sets
```

Rerun it per release rather than keeping a set around: the seed shifts the
example document's timestamps so the newest entry ended two hours ago, and a
stale set quietly shows a stale week.

#### The screenshot trap, which is Play-specific

Play accepts 320–3840px a side for phones and 1080–7680px for tablets, and
enforces one rule that catches nearly everyone: **the long side may not be more
than twice the short side.** Every stock modern phone AVD is 1080×2400, which
is 2.22∶1 and refused. The existing `docs/screenshots/` set has exactly this
problem, which is a second reason not to reuse it for the listing.

So the script wants two purpose-made emulators, `cirrhy_phone` and
`cirrhy_tablet` (override with `$CIRRHY_PHONE_AVD` / `$CIRRHY_TABLET_AVD`).
Create them in Android Studio's Device Manager, or with `avdmanager`, and set
the resolution explicitly in the AVD's hardware profile:

| AVD | Resolution | Ratio | Why |
|---|---|---|---|
| `cirrhy_phone` | 1080×1920, 420dpi | 9∶16 | exactly at Play's cap, and its recommended phone minimum |
| `cirrhy_tablet` | 1600×2560, 320dpi | 5∶8 | comfortably inside the cap, above the 1080px tablet floor, and wide enough to show the 220px rail rather than the phone layout |

The tablet number is not arbitrary: the adaptive shell switches to the rail
above 900px logical width, so a tablet screenshot taken at phone density shows
the phone UI and sells the wrong thing entirely (`app/lib/shell/`).

The script asserts Play's rules against what actually came out rather than
trusting the device, and refuses a set where all three captures are
byte-identical — the failure mode where the surface never painted and every
file is the same blank frame at exactly the right size.

The two remaining graphics come out of the icon generator, from the same source
mark as every app icon, so the store page and the launcher cannot drift apart:

```sh
python3 tool/gen_app_icons.py
#   assets/icon/play-store-512.png          512×512 listing icon
#   assets/icon/play-feature-graphic.png    1024×500 feature graphic, required
```

## Each release

### Build

The Android SDK needs **cmdline-tools** installed. It is the one prerequisite
`flutter doctor` flags that actually blocks a release bundle, and the way it
fails is thoroughly misleading: Gradle succeeds, the `.aab` is written, and
then the build aborts with

```
Release app bundle failed to strip debug symbols from native libraries.
```

Nothing was wrong with the stripping. Flutter *verifies* that the native
libraries were stripped by running `apkanalyzer`, which lives in cmdline-tools;
with those missing the check cannot run, so it answers "not stripped" and the
build fails. Install them in Android Studio (SDK Manager → SDK Tools → Android
SDK Command-line Tools) or with `sdkmanager "cmdline-tools;latest"`.
`tool/target-android.sh` warns about this before it starts a bundle build,
which is three minutes earlier than finding out the hard way.

For a first attempt, or any time you want a bundle without cutting a release:

```sh
tool/target-android.sh --release --aab
```

It prints whether the result is upload-signed or debug-signed before it starts,
which is the one thing worth reading — a debug-signed bundle uploads fine right
up until the Console rejects it.

Once that works, the normal path is the release script, which bumps
`app/pubspec.yaml` (including the `+N` build number — Play requires the
`versionCode` to **increase on every upload**, including uploads that are
never released), bumps the About screen's `appVersion`, runs the suite, tags,
pushes, and then prepares the store packages:

```sh
tool/release.sh <version>       # → dist/cirrhy-<version>-playstore.aab
```

### Verify before uploading

Two checks against the artifact rather than the source, both cheap:

```sh
# Who signed it — compare against tool/android-signing.sh's output, and
# against "Upload key certificate" in the Console.
keytool -printcert -jarfile dist/cirrhy-<version>-playstore.aab

# What it asks the OS for. The source manifests are unit-tested, but only the
# built bundle shows permissions merged in from dependencies.
bundletool dump manifest --bundle=dist/cirrhy-<version>-playstore.aab \
  --xpath=/manifest/uses-permission/@android:name
```

`bundletool` is a separate download from Google; `keytool` ships with the JDK
the build already needs. The expected permission output is exactly
`POST_NOTIFICATIONS` and the Huawei `CHANGE_BADGE`. Anything else — above all
`INTERNET` or `AD_ID` — means a dependency changed what the app is, and the
Data safety declaration needs revisiting before the upload, not after.

### Upload

Play Console → **Test and release → Testing → Internal testing → Create new
release**, and drag the `.aab` in. Internal testing needs no review and is
available within minutes, which proves signing, upload and install on a real
device while mistakes are still cheap. Install it from the opt-in link on an
actual phone before going further; it is the Android equivalent of TestFlight
first, and it is the step that catches a broken upload key immediately rather
than at the end of a production review.

### Promote to production

**Production → Create new release**, promoting the same bundle rather than
building a second one, then fill the release notes (from the listing document)
and submit.

Two Console settings worth knowing before you need them:

- **Staged rollout** releases to a percentage of users. For an app with no
  crash-reporting service to watch — Cirrhy has none, by design — a staged
  rollout is mostly a way to limit how many people see a bad build before a
  review surfaces it. Starting at 20% for the first release costs nothing.
- **Managed publishing** holds an approved release until you press the button,
  rather than going live the moment review finishes. Useful when the listing
  copy and the binary should land together.

Review for a first release commonly takes a few days, and can take longer for a
recently created developer account. Updates are usually faster, but "usually"
is not a plan — do not tag a release the day it has to be live.

### When it goes live

Three edits, all deliberately left undone until the listing actually exists,
because a README that claims a store page before there is one is the kind of
inaccuracy nobody notices they are making:

1. **`README.md`, Status section.** "There is no Play listing yet, so Android
   means the APK above or a source build" becomes the Play badge and link,
   alongside the existing App Store one. Keep the sentence about the APK — it
   stays the answer for anyone without a Google account.
2. **`README.md`, Thanks section.** Appific "publish Cirrhy on the App Store"
   becomes both stores.

Nothing else. The privacy policy already covers both stores, and
`docs/legal/support.md` names no store at all — it routes everything through
the issue tracker, which does not change.

### The Play Console warning that is expected

After each upload the Console notes that the bundle contains native code
without debug symbols. That is normal for a Flutter app and is not worth
chasing: the native libraries are the prebuilt, already-stripped Flutter engine,
and a crash in Cirrhy's own code is Dart, which those symbols would not explain
anyway. The tool that does explain it is `flutter symbolize` against the output
of `--split-debug-info`, which this project does not currently produce. Adding
it means keeping a symbol directory per released version somewhere findable,
which is a real commitment; worth making the day the first unexplained crash
report arrives, and not before.

## Other stores

- **F-Droid** is the natural third home for this app and needs no work here:
  Apache-2.0, reproducible from source, no proprietary dependencies, and no
  network code to audit. It builds from the repository rather than from an
  upload, so it needs a metadata submission rather than a release process.
- **The GitHub Releases APK stays** regardless. It is the answer for anyone
  who wants Cirrhy without a Google account, and it costs nothing — CI already
  builds it.
- **Amazon Appstore / Huawei AppGallery** would each take the same `.aab` or an
  APK, and each add their own account, review queue and store listing. The
  Huawei badge support in `TimerBadge.kt` exists because of a physical device,
  not because of AppGallery.
