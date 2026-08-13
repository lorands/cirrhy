# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

**Stack confirmed: Flutter** (2026-08-13). A pub workspace with two members:

- `packages/cirrhy_merge` — the storage and merge engine. Pure Dart, zero UI dependencies, only `crypto`. This is where the data-loss risk lives; it is fully tested headless.
- `app` — the Flutter app, five targets. Depends on the engine; the engine never depends on it.

Built against Flutter 3.44.8 / Dart 3.12.2. Run everything from the repo root:

```sh
flutter pub get                        # resolves the whole workspace; also runs gen-l10n
tool/check.sh                          # analyze + report formatting
tool/test.sh                           # engine (30 tests) then app (22)

tool/dev.sh                            # desktop + mobile side by side, one hot reload
tool/run-android.sh                    # start one frontend; run-{linux,macos,ios,windows} too
tool/host-auto.sh                      # build everything this host can
tool/target-linux.sh                   # one target; --debug default, --release opt-in
```

`flutter build` resolves `lib/main.dart` against the working directory, so it only works from `app/`, never the workspace root. The `tool/` scripts handle that themselves — see `tool/README.md`.

There is **no UI yet**, deliberately — DESIGN.md §9 puts the engine first. `app/lib/main.dart` is a placeholder that wires the theme and nothing else. `app/lib/theme/` mirrors the Penpot token library; keep the two in step.

`DocumentStore` (DESIGN.md §4.1) is the unimplemented piece: the platform port for file access. Everything above it is plain Dart.

## Languages

Ships **hu, en, es, it, de**, and the set has to stay open — adding a language must never mean touching code.

It doesn't. Drop `app/lib/l10n/app_<code>.arb` next to its siblings, add the code to `shipped` in `app/test/l10n_test.dart`, and run `flutter pub get`. Nothing enumerates the locales: `l10n.yaml` points gen-l10n at the directory and it discovers what is there. `app_en.arb` is the template — every other file must carry exactly its keys, which `l10n_test.dart` enforces rather than trusting.

Two traps the tests exist to catch:

- **gen-l10n sorts `supportedLocales`, so `de` comes first.** Flutter's stock resolution falls back to `supportedLocales.first`, which would hand German to a Japanese device. `resolveLocale` in `main.dart` pins the fallback to English; do not delete it, and do not assume adding a language leaves it alone.
- **A locale missing a key silently inherits English.** The generated class hides this, so the test compares the ARB files directly.

Strings live in ARB with a `@key` description for anything a translator could misread. `appTitle` is the brand and stays "Cirrhy" everywhere; `languageName` is each language's name in itself (Magyar, not Hungarian), for the picker a settings screen will need.

**The OS language is the default; the user can override it.** `LocalePreference` (`app/lib/settings/locale_preference.dart`) holds a nullable `Locale`, where null means "follow the system" and is the normal state — there is no "system" sentinel language code to special-case.

It is stored in **platform preferences, not the Cirrhy document**, and that is the load-bearing part. DESIGN.md §3.6 keeps device-scoped state out of last-write-wins merge, using the running timer as the case; a language is the same shape. A Hungarian phone and an English work laptop are both legitimate, and a synced language would flip one device's UI because you changed it on the other. It also keeps the single-file promise about *tracking data* rather than every preference. Do not move it into the document.

A stored language the app no longer ships is ignored rather than honoured, so dropping a translation cannot strand someone in a language with no strings left.

The picker currently sits on the placeholder screen. That is scaffolding so the choice can be exercised on a real device before a settings screen exists — move it when settings is designed; `LocalePreference` does not change.

Dates, times and durations are the reporting feature's core output and must go through `intl` formatters, never hand-built strings — `1.5 h`, `1,5 óra` and `1,5 Std.` all differ by more than the decimal mark.

## App icons

Every platform's icon is **generated, never hand-edited**:

```sh
python3 tool/gen_app_icons.py          # needs rsvg-convert + magick
python3 tool/gen_app_icons.py --recrop # also re-derives the mark from logo-1.svg (needs inkscape)
```

The source is `assets/logo/cirrhy-mark.svg` — `logo-1.svg` cropped to its drawing bounds. Geometry and colour come from Penpot page `08 · Brand & Logo`, card `App icon`; the script's header records the measurements. Change the design there, then re-run — the same rule as `app/lib/theme/`.

Two things in the script that look like mistakes but are not. The mark sits slightly below centre, because the hands reach up and right. And below ~128px it gets a stroke in its own fill colour, because the artwork's hairlines are ~0.9 units across a 64.6-unit viewBox and antialias into a grey ghost at launcher sizes; above that the boost is zero and the pixels are exactly what the design draws.

Editing `app/linux/runner/resources/` by hand is wasted work for the same reason — the hicolor tree and the `.desktop` file are both generated.

## What Cirrhy is

A personal time tracker (name = **Circadian Rhythm**), built out of frustration with Clockify/Toggl/Kimai. Take their feature set, strip the team dimension, keep it simple.

Product constraints that drive nearly every design decision:

- **Single-user, not teams.** No accounts, no sharing, no permissions model. Anything that implies multi-user is out of scope.
- **Multi-lingual, extensibly.** hu, en, es, it, de at minimum, with adding a sixth costing one file. See [Languages](#languages). No user-visible string is ever a literal in a widget.
- **All data in a SINGLE FILE.** Sync is the user's problem — they drop the file in Dropbox/Syncthing/whatever. The app must never depend on a specific sync service, and must not assume it owns the file exclusively. See [Storage and merge](#storage-and-merge) — this is the load-bearing decision in the project.
- **Five targets: iOS, Android, Linux, macOS, Windows.** The chosen stack has to cover mobile and desktop, which rules out most desktop-only or web-only toolkits.
- **Domain shape:** clients → projects → tasks, with time entries hanging off them. Reporting over an arbitrary timespan with filters and multiple views is a first-class feature, not an afterthought.
- **Main screen:** the running timer plus recent logged work; each past entry has a run icon that starts a new timer from it. This one-tap-restart flow is the primary interaction — design the entry model so restarting from a past entry is trivial.

## Architecture

**`DESIGN.md` is the source of truth for architecture, and carries the full rationale plus references.** Read it before proposing anything about storage, merge, file access, format, or stack. Keep it updated when decisions change — do not restate its contents here.

The non-negotiables it establishes, so they are visible without a second file read:

- **Merge at the record layer, never the file layer.** Every record has a stable UUID and last-modified timestamp; merge is a union over UUIDs with newer-wins. Saving is always **read-merge-write** against what is currently on disk, never blind overwrite. Detect change by **content hash, not mtime**.
- **Deletions need tombstones** (UUID + deletion time). Without them every merge silently resurrects deleted records.
- **Per-record history**, so the loser of a last-write-wins conflict is demoted rather than destroyed.
- **Never field-merge a time entry** — start/stop merge as a unit, or you produce a duration nobody recorded.
- **The running timer is per-device, keyed by device ID.** Last-write-wins on it silently discards a tracked interval.
- **File access is an OS-provided file handle. Cirrhy contains no network or cloud-provider code.** WebDAV/SFTP/Dropbox clients were considered and rejected — see DESIGN.md §4 before re-raising.
- **No SQLite** — its `-wal`/`-shm`/`-journal` sidecars break the single-file promise.

Still **Proposed, not confirmed**: JSON vs CBOR. JSON ships today behind a `DocumentCodec` interface, so swapping it does not reach into the merge engine — but it changes the on-disk format, so decide before real data exists.

Two engine invariants that tests enforce and any change must preserve: the merge is **commutative** (`merge(a, b) == merge(b, a)`, ties included) and **idempotent**. Without both, the result depends on which side was passed first.

## License and naming

Apache 2.0; identity is rooted at `com.lorands.cirrhy`. Full detail in `DESIGN.md` §7. Day-to-day rules:

- New source files get the standard short Apache header, `Copyright 2026 Lóránd Somogyi` — accented. The ASCII `lorands`/`lorand.somogyi` in the domain and email are transliterations, not the name. Keep sources UTF-8.
- `LICENSE` is verbatim upstream text; never edit it, including its appendix placeholders.
- No `NOTICE` file, deliberately — adding one obliges every downstream redistributor under §4(d).
- Apache 2.0 cannot incorporate **GPLv2-only** code. Check any dependency's license before proposing it.

## Environment

- Linux Manjaro is the primary dev machine; a MacBook Pro is also available (needed for iOS builds).
- Containers via **podman**, not docker. `docker` commands generally work as `podman` equivalents, but write scripts against podman.
- Flutter is installed system-wide. **devbox was tried and dropped** (2026-08-13) — it earned nothing here, and DESIGN.md §6 already notes Flutter pins badly under nix/devbox because the SDK self-updates and pulls prebuilt engine binaries. Do not reintroduce a toolchain manager without a concrete reason.
- Penpot (design/mockups) with MCP is self-hosted at http://192.168.50.138:31027/ — check it for design intent before inventing UI.
