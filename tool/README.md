# tool/

Build, run and asset scripts. Everything here runs from anywhere — each script
locates the repo root itself and `cd`s into `app/`, because `flutter build`
resolves `lib/main.dart` relative to the working directory and fails from the
workspace root.

## Developing against two outlines at once

```sh
tool/dev.sh
```

Runs the host's desktop build and its mobile build side by side, with one hot
reload driving both:

| Host | Desktop | Mobile |
|---|---|---|
| Linux | Linux | Android |
| macOS | macOS | iOS |
| Windows | Windows | Android |

Output is prefixed per device (`[linux]`, `[android]`). One `r` reloads both,
`R` restarts both, `q` quits both.

A physically attached phone always wins over an emulator. With nothing
attached, the first available emulator or simulator is booted automatically.
`--desktop-only` and `--mobile-only` narrow it to one.

Two things worth knowing about how it works. Each `flutter run` gets its stdin
from `/dev/null` and is driven by the `--pid-file` signals flutter documents —
`SIGUSR1` for reload, `SIGUSR2` for restart — because two interactive flutter
consoles would otherwise fight over the terminal. And it does not use
`flutter run -d all`, which would also pick up the Chrome device this project
has no web target for.

## Checking

```sh
tool/test.sh              # engine suite, then app suite
tool/check.sh             # flutter analyze, then a formatting report
```

`check.sh` reports formatting rather than failing on it. `app/lib/theme/tokens.dart`
is committed in a shape `dart format` disagrees with — its aligned colour
tables read better than the formatter's output — and failing the build on that
would only teach people to skip the script.

## Starting one frontend

```sh
tool/run-linux.sh         # Linux host only
tool/run-macos.sh         # macOS host only
tool/run-ios.sh           # macOS host only
tool/run-windows.sh       # Windows host only
tool/run-android.sh       # any host with the Android SDK
```

Each starts that platform's frontend and hands you flutter's own console — the
full `r`/`R`/`q` set, since a single run has no one to share the terminal with.
Device choice works exactly as in `dev.sh`: attached hardware wins, an emulator
is booted only if nothing is plugged in. Override with `-d`:

```sh
tool/run-android.sh -d emulator-5554
tool/run-android.sh --profile -- --trace-startup
```

They take the same `--debug` / `--profile` / `--release` and `--` passthrough
as the build scripts.

## Building

Per target — each refuses to run on a host that cannot build it:

```sh
tool/target-linux.sh      # Linux host only
tool/target-macos.sh      # macOS host only
tool/target-ios.sh        # macOS host only
tool/target-windows.sh    # Windows host only
tool/target-android.sh    # any host with the Android SDK
```

Everything one host can build, with a summary of what was skipped and why:

```sh
tool/host-linux.sh        # Linux + Android
tool/host-macos.sh        # macOS + iOS + Android
tool/host-windows.sh      # Windows + Android
tool/host-auto.sh         # detects the host, runs the matching one — use this in CI
```

All of them take `--debug` (the default), `--profile` or `--release`, and pass
anything after `--` straight through to flutter:

```sh
tool/target-android.sh --release -- --split-per-abi
```

Debug is the default deliberately: Android quietly debug-signs, and iOS needs
a development team before `--release` means anything. Two target-specific
flags exist for that — `tool/target-android.sh --aab` for the Play Console
format, and `tool/target-ios.sh --codesign` once a team is set.

## Releasing

```sh
tool/release.sh 0.2.0            # bump, commit, tag v0.2.0, push, store packages
tool/release.sh 0.2.0 --force    # redo a tag that failed CI's verify
```

One command in the order that works: bumps the version everywhere it lives —
`app/pubspec.yaml` (and its `+N` build number, which the Play Console
requires to grow with every upload) *and* the About screen's `appVersion`
constant in `app/lib/about/version.dart`, which a test pins to pubspec —
commits, runs the full test suite locally, then tags `v<version>` and pushes
branch and tag. The tag push is the release — CI verifies the tag against
pubspec, re-runs the suite, builds the four platform packages and publishes
the GitHub release. Tagging before bumping is exactly what the verify job
refuses, and exactly the mistake this script makes impossible; the local
suite run catches what a half-bump would break while it still costs seconds.

`--force` moves an existing tag — the recovery for one that failed verify —
and force-pushes it; CI adopts the existing GitHub release and replaces its
assets rather than failing.

After the push it prepares the app-store packages it honestly can, into
`dist/` (gitignored): the Play Console `.aab` on any host with the Android
SDK, upload-signed once `tool/android-signing.sh` has configured a key and
debug-signed before that; and the App Store `.ipa` only on a macOS host with
a signing team set (`tool/ios-signing.sh`), which further needs a paid
membership, because a free personal team cannot sign for distribution. Each
says which it produced rather than leaving you to find out at the store.
`--no-stores` skips this stage, `--yes` the push confirmation.

## Desktop integration on Linux

```sh
tool/install-linux.sh               # newest built bundle, release preferred
tool/install-linux.sh --debug       # pin the mode instead
tool/install-linux.sh --uninstall
```

Installs the generated `.desktop` entry and hicolor icons into
`~/.local/share`, with `Exec` pointing at the built bundle where it lies. This
is what puts Cirrhy's own icon on the taskbar: a Wayland compositor never asks
a window for its icon — it matches the window's app id against installed
`.desktop` files, and without a match KDE and GNOME show the generic cog. The
match covers every launch of the app id, `flutter run` dev sessions included.
The bundle is not copied; re-run after moving the repo.

## Signing for iOS

```sh
tool/ios-signing.sh                 # what is set, and what could be
tool/ios-signing.sh ABCDE12345      # set it
tool/ios-signing.sh --clear         # back to simulator-only
```

A physical iPhone cannot be run on or installed to without a development
team. Which Apple ID supplies it is a property of the machine rather than of
the project, so the setting is written to `app/ios/Flutter/Signing.xcconfig`,
which is gitignored and which `Debug.xcconfig` and `Release.xcconfig` pull in
with an **optional** include — a clone with no Apple ID still builds for the
simulator, and nobody's team ID lands in the repository.

A free personal team is enough here: the iOS target declares no entitlements
at all, so nothing needs a paid membership. It signs builds for your own
devices and nothing more — no TestFlight, no App Store, seven-day expiry,
three apps per device.

Installing a release build on an attached, paired iPhone with Developer Mode
on:

```sh
tool/run-ios.sh --release
```

It stays installed and launches on its own after you quit flutter's console.
When a personal team's seven days lapse the app stops launching; re-running
that command reinstalls over the top, which keeps the chosen data folder
because the bookmark lives in the app's preferences.

## Signing for Android

```sh
tool/android-signing.sh                    # what is set, and its fingerprint
tool/android-signing.sh --create           # mint an upload keystore
tool/android-signing.sh ~/keys/cirrhy.jks  # point at an existing one
tool/android-signing.sh --clear            # back to debug-signed releases
```

The counterpart of `tool/ios-signing.sh`, and the same argument: which key
signs a build says nothing about the project, so the setting goes to
`app/android/key.properties`, which is gitignored and which
`app/android/app/build.gradle.kts` reads. No file, no signing config, and a
`--release` build falls back to debug keys — installable, not publishable,
and the build scripts say which you got.

Unlike iOS, a release build works without this: Android debug-signs quietly,
which is what the CI-built APK on the Releases page is. The key only matters
for uploading to the Play Console.

What it makes is the **upload key**, not the app signing key. Under Play App
Signing, Google holds the key devices verify and it never leaves them; the
upload key only proves an upload came from you, and a lost one is reset from
the Console in a couple of days rather than being fatal. Back up the keystore
and `key.properties` together anyway — the passwords live in the second file
— and note the keystore defaults to `~/.cirrhy/`, outside the repo, where a
`git clean` cannot reach it. `docs/release/play-store.md` is the full story.

## Icons

```sh
tool/gen_app_icons.py
```

Regenerates every platform's app icon from `assets/logo/cirrhy-mark.svg`,
including the running-timer companions (the badged icons for the Linux and
macOS swap, Windows' overlay dot, Android's notification glyph). See the
script's header and the App icons section of `CLAUDE.md` — the geometry comes
from Penpot and is not to be nudged by hand.

## Store screenshots

```sh
tool/gen_screenshots.sh                 # every set this host can produce
tool/gen_screenshots.sh --iphone        # only the App Store 6.9" set
tool/gen_screenshots.sh --android       # both Play sets
tool/gen_screenshots.sh --locale hu     # a localized set
```

Four sets, two stores: `iphone` and `ipad` for the App Store, `phone` and
`tablet` for Play. The Apple two need a Mac; the Android two need only the
SDK, so the Linux machine can produce them. Each runs the real app on a real
device against a seeded copy of `docs/reporting/cirrhy.json` and taps between
the tabs — `app/integration_test/screenshots_test.dart` does the driving and
`tool/gen_screenshot_seed.py` builds the document. What lands in
`app/build/screenshots/` is the shipping UI at device resolution.

Every capture is checked before the script reports it, because both stores
reject the wrong size and neither tells you quickly. Apple wants exact pixel
dimensions, so those are asserted against a number. Google wants a range —
320–3840px a side for phones, 1080–7680 for tablets — plus a rule that
catches people out: **the long side may not exceed twice the short side**,
which rules out every stock 1080×2400 phone AVD. `docs/release/play-store.md`
has the two AVDs to make instead. A set where every capture is byte-identical
is refused too: that is the surface never having painted, which produces
blank frames at exactly the right size.

The Android path has one extra moving part. A simulator shares the Mac's
filesystem and can read the seed document straight off it; an emulator cannot
see the host at all, so the script `adb push`es the seed into the app's own
external files directory and the test finds it there.

Generated rather than hand-captured for the same reason as the icons: a
screenshot taken by hand is one nobody can reproduce next release. Rerun per
release — the seed shifts the example document so the newest entry ended two
hours ago, and a stale set shows a stale week.
