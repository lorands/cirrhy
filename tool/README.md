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

Debug is the default deliberately: nothing here is signed yet, so `--release`
fails outright on iOS and quietly debug-signs on Android. Two target-specific
flags exist for that — `tool/target-android.sh --aab` for the Play Console
format, and `tool/target-ios.sh --codesign` once a development team is
configured in Xcode. A physical iPhone cannot be run or installed on without
one.

## Icons

```sh
tool/gen_app_icons.py
```

Regenerates every platform's app icon from `assets/logo/cirrhy-mark.svg`. See
the script's header and the App icons section of `CLAUDE.md` — the geometry
comes from Penpot and is not to be nudged by hand.
