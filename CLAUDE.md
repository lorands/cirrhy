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
tool/test.sh                           # engine (33 tests) then app (263)

tool/dev.sh                            # desktop + mobile side by side, one hot reload
tool/run-android.sh                    # start one frontend; run-{linux,macos,ios,windows} too
tool/host-auto.sh                      # build everything this host can
tool/target-linux.sh                   # one target; --debug default, --release opt-in
```

`flutter build` resolves `lib/main.dart` against the working directory, so it only works from `app/`, never the workspace root. The `tool/` scripts handle that themselves — see `tool/README.md`.

Releases: pushing a `v*.*.*` tag runs `.github/workflows/release.yml` — a verify job (the tag must equal `app/pubspec.yaml`'s version, so bump pubspec before tagging; then `check.sh` + `test.sh`), four platform packages (Linux tar.gz, debug-signed Android APK, untested-Windows zip, unsigned-macOS zip), and a GitHub release with checksums. iOS is deliberately absent — an installable build needs a signing identity CI should not hold.

The main screens exist as of 2026-08-14: an adaptive shell (`app/lib/shell/` — bottom tab bar under 900px, 220px rail above) hosting Timer (`app/lib/timer/`, incl. start sheet, task picker and entry editor), Projects (`app/lib/projects/`), Reports (`app/lib/reports/`), and Settings/About (`app/lib/settings/`, still doubling as first run), plus the sync-visibility layer (`app/lib/sync/`: foreign-timer reconciliation, merge snackbar, folder-unreachable dialog). All document access goes through one object — `DocumentSession` (`app/lib/data/document_session.dart`), a ChangeNotifier owning the serialized read-merge-write commit queue; screens never touch `DocumentRepository` directly. `app/lib/theme/` mirrors the Penpot token library; keep the two in step (`tokens.dart` is deliberately hand-aligned — never run `dart format` over it). Penpot page `09 · Screens & Flow` (added 2026-08-13) mocks every screen and the navigation between them — 24 screens in seven groups, drawn from the sheets-01–08 tokens and components; build against it rather than inventing UI. One deliberate motif, implemented in `app/lib/shell/watermark.dart`: every screen carries the logo as a barely-perceptible watermark (~5% opacity) that is anchored to the viewport — content scrolls over it, the mark never moves. Not built yet from the mockups: a "Source code" About row (no public URL), device names on foreign timers (needs a document field), and the desktop-only side panels on G1/G2. The mockups' beside-the-file backups toggle became the "Back up now" action in the Data folder section (DESIGN.md §11, built 2026-08-15).

`DocumentStore` (DESIGN.md §4.1) is implemented on all five platforms — see [Where the file lives](#where-the-file-lives).

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

The picker lives on the preferences screen, where it moved off the placeholder once that screen existed. `LocalePreference` did not change in the move, and should not.

Dates, times and durations are the reporting feature's core output and must go through `intl` formatters, never hand-built strings — `1.5 h`, `1,5 óra` and `1,5 Std.` all differ by more than the decimal mark.

## Where the file lives

The user picks a **folder** at first run and can change it later; both are the same screen (DESIGN.md §4.6). The app is gated until a folder is chosen — a default location was considered and dropped, so do not reintroduce one without reading why.

The parts that will bite whoever touches this next:

- **The choice is device-scoped**, stored in platform preferences exactly like the language, and must never move into the document. Here the argument does not even need merge semantics: an iOS bookmark is meaningless on Linux.
- **Directory scope, not file scope**, decided 2026-08-13. A document-scoped handle cannot write a sibling temp file, so every save would degrade to in-place overwrite. Asking for a folder is what makes the atomic write possible.
- **The file name is fixed** (`cirrhy.json`, `documentFileName`) and never asked. It is what the adopt rule keys on: a chosen folder that already holds a Cirrhy document is opened and **merged**, not replaced, which is what makes setting up the second device the same flow as the first. `knownDocumentFileNames` is the one place that learns a second name if §5 lands on CBOR.
- **Relocating is a save, not a settings write.** Point the store at the new handle and read-merge-write does the rest, including the case where the target already holds a document. The old file is left where it is.

Two platform-shaped facts that look like mistakes and are not:

- **macOS is an Apple platform here, not a desktop one.** Flutter's macOS template enables App Sandbox, so a picked path works until the first restart and then stops. macOS uses a security-scoped bookmark like iOS, and the two entitlements files carry the grants that make that work.
- **Android writes in place.** SAF has no replace-over-existing, so the pre-write backup is not belt-and-braces there, it is the whole recovery story.

Linux and Windows need no native code — a path is a durable handle, and `file_selector` supplies the dialog. The other three go through one channel, `com.lorands.cirrhy/documents`, implemented in `android/.../DocumentFolders.kt`, `ios/Runner/AppDelegate.swift` and `macos/Runner/MainFlutterWindow.swift`. **The two Swift files are near-duplicates on purpose**: sharing one file across the two Xcode targets means hand-editing both project files, which is a worse trade than keeping two short files in step. Backups are plain `dart:io` on all five, because app-private storage is a real path everywhere.

**Linux, the Android emulator, macOS and iOS are verified.** Android's SAF path ran end to end on an API 36 emulator on 2026-08-14 (pick, adopt, read, write — the first write also caught a `kotlin.Unit`-over-the-channel crash, fixed in `DocumentFolders.kt`). The two Swift implementations were built and tested on the MacBook on 2026-08-14. Windows remains scaffolded but untested; say so rather than implying otherwise.

## App icons

Every platform's icon is **generated, never hand-edited**:

```sh
python3 tool/gen_app_icons.py          # needs rsvg-convert + magick
python3 tool/gen_app_icons.py --recrop # also re-derives the mark from logo-1.svg (needs inkscape)
```

The source is `assets/logo/cirrhy-mark.svg` — `logo-1.svg` cropped to its drawing bounds. Geometry comes from Penpot page `08 · Brand & Logo`, card `App icon`; the script's header records the measurements. Change the design there, then re-run — the same rule as `app/lib/theme/`. The tiles became brand-ramp **gradients** and the mark a constant optical weight on 2026-08-15 (a flat tile with hairlines read as a green blob at launcher sizes); the script header records the stops, **Penpot's card still shows the old flat tile and needs bringing in step**.

Two things in the script that look like mistakes but are not. The mark sits slightly below centre, because the hands reach up and right. And the mark is stroked in its own fill colour up to a constant ~2.2 units across its 64.6-unit viewBox — constant on purpose, because raster size stopped predicting physical size (a 192px xxxhdpi launcher icon is ten millimetres wide); only favicon-class sizes get more, via the MIN_STROKE_PX floor.

The script also emits the running-timer companions: `-running` hicolor icons (Linux), the `AppIconRunning` imageset (macOS dock), `badge_overlay.ico` (Windows taskbar), and `ic_stat_timer` (the Android notification's status-bar glyph).

Editing `app/linux/runner/resources/` by hand is wasted work for the same reason — the hicolor tree and the `.desktop` file are both generated.

**The Linux taskbar icon needs an install step**: `tool/install-linux.sh` puts the `.desktop` entry and icons into `~/.local/share`, because a Wayland compositor resolves icons by matching the window's app id against installed `.desktop` files — it never asks the window. Without it the taskbar shows the generic Wayland cog, `flutter run` sessions included.

## Running-timer badge

While this device's timer runs, the launcher icon carries a badge. One Dart service (`app/lib/timer/timer_badge.dart`, owned by the shell, tested in `timer_badge_test.dart`) watches `DocumentSession.myTimer` — deliberately not foreign timers, which would make every synced device's icon cry wolf — and pushes over `com.lorands.cirrhy/badge`. All notification strings travel localized from the ARB files; the platform sides hold no literals. Per platform:

- **Linux** (`my_application.cc`): swaps the window icon to `-running` (X11) and emits the Unity LauncherEntry count signal — KDE and most docks render it, stock GNOME Shell needs a dock extension, and it keys off the installed `.desktop` file (see above). Verified on this machine's build.
- **macOS** (`MainFlutterWindow.swift`): swaps `NSApp.applicationIconImage` to `AppIconRunning`; nil restores the bundle icon. `dockTile.badgeLabel` was rejected — it renders as an unread-count bubble.
- **Windows** (`flutter_window.cpp`): `ITaskbarList3::SetOverlayIcon` with `badge_overlay.ico`. Compiles untested, like the rest of the Windows target.
- **Android** (`TimerBadge.kt`): a silent ongoing notification in a badge-enabled channel — launcher dot, live chronometer in the shade, tap opens the app. Android 13+ asks for `POST_NOTIFICATIONS` the first time a timer starts; refusal costs only the badge. Huawei/Honor launchers ignore notification dots outright, so on those the count is also pushed to EMUI's own badge provider (found the hard way on the Mate 10 Pro, 2026-08-15).
- **iOS** (`AppDelegate.swift`): badge count 1, behind a `.badge`-only authorization prompt on first start; refusal costs only the badge.

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
- **Recovery is record-level, through the format — never file-level.** Restoring a backup by copying it over `cirrhy.json` is defeated by merge (an offline device's tombstones re-kill the restored records days later); archiving old records to a second file resurrects or bloats. Both are explicit rejections — see DESIGN.md §11 before re-raising either.
- **No SQLite** — its `-wal`/`-shm`/`-journal` sidecars break the single-file promise.

The format is **Decided: JSON** (2026-08-14, DESIGN.md §5) — settled when §10 made the file format the import seam. The `DocumentCodec` interface and `knownDocumentFileNames` stay as the escape hatch; a format change is possible, not pending. Import (§10) is likewise **Decided**: a one-time, agent-driven migration written straight into the live file, made safe by two provenance fields on every record (`importSource`, `externalId` — traceability only, never merge keys) and a rollback protocol of "tombstone the batch, re-import". All built as of 2026-08-14: the fields (formatVersion bumped to 2), plus the JSON Schema and agent-facing spec in `packages/cirrhy_merge/doc/` — a schema-sync test keeps those two in step with the codec, so a new record field means updating the schema or that test fails. App code that rebuilds an existing record field-by-field must carry `importSource`/`externalId` through (every current site does; follow the `history: current.history` idiom).

Reporting beyond the app rides the same seam (§12, **Decided** 2026-08-15): heavy analysis is an agent job through the format, never app surface. Three artifacts keep the claim honest, each with its own tether: `.claude/skills/cirrhy-report` bundles **verbatim copies** of the schema and `llms.md` (`skill_sync_test.dart` fails on drift — `doc/` is canonical, edit there and re-copy); `docs/reporting/cirrhy.json` is the full-size example document, generated by `tool/gen_example_document.py` and never hand-edited (`example_document_test.dart` keeps it decodable and byte-canonical, so regenerate rather than touch it); `docs/reporting/README.md` shows the worked prompt→artifact examples.

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
