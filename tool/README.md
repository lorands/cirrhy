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

## Icons

```sh
tool/gen_app_icons.py
```

Regenerates every platform's app icon from `assets/logo/cirrhy-mark.svg`,
including the running-timer companions (the badged icons for the Linux and
macOS swap, Windows' overlay dot, Android's notification glyph). See the
script's header and the App icons section of `CLAUDE.md` — the geometry comes
from Penpot and is not to be nudged by hand.
