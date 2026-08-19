# Cirrhy — Design

Status of this document: working design, 2026-08-13. Nothing is implemented yet.

Each decision below is tagged **Decided**, **Proposed** (my recommendation, not yet confirmed), or **Open**.

---

## 1. Product

Cirrhy (from *circadian rhythm*) is a personal time tracker. Take Clockify/Toggl/Kimai, remove the team dimension, keep what's left simple.

- **Single user.** No accounts, no sharing, no permissions, no server. Anything implying multi-user is out of scope.
- **All data in one file**, which the user syncs however they like.
- **Five targets:** iOS, Android, Linux, macOS, Windows.
- **Domain:** clients → projects → tasks, with time entries attached. Reporting over an arbitrary timespan with filters and multiple views is a first-class feature.
- **Main screen:** the running timer plus recently logged work. Every past entry has a run icon that starts a new timer from it. This one-tap restart is the primary interaction, and the data model should make it trivial.

---

## 2. The core problem

One file, edited on up to five devices, synced by a service we neither control nor know about. Two devices can legitimately edit while offline and reconcile later.

**This cannot be solved at the file layer.** Locking, mtime comparison and conflict-copy handling all fail once an opaque sync client is in the loop. It has to be solved at the *record* layer, with a merge that understands the data.

This is exactly the problem KeePass solves for KDBX, so we follow its design. KeePass's own documentation calls the merge algorithm "rather complex" and declines to specify it fully — the notes below are the parts that matter for us.

---

## 3. Data model and merge — **Decided**

### 3.1 Record identity

Every record carries a **stable UUID** and a **last-modified timestamp**. Merge is a union over UUIDs; where both sides hold the same UUID, the newer timestamp wins. Never merge positionally or by array index.

KeePass merges at entry granularity deliberately — it guarantees a username/password pair stays mutually consistent rather than field-merging into a combination that never existed. Our equivalent: a time entry's start and stop must merge as a unit. Never field-merge a `start` from one device with a `stop` from another; the result is a duration that nobody recorded.

### 3.2 Saving is read-merge-write

On every save: re-read what is currently on disk, merge it with in-memory state, write the result. Never blind-overwrite.

KeePass detects that the file changed since load and *prompts* the user to overwrite or synchronize. We should **merge automatically** — a single user with no team has nobody to arbitrate with, and a prompt they can't meaningfully answer is worse than a correct default.

Detect change by **content hash, not mtime**. Keepass2Android hashes the bytes it loaded and compares before writing; sync-service mtimes are not trustworthy.

### 3.3 Tombstones

Deletions are recorded, not just applied. KDBX keeps a `DeletedObjects` list of UUID + deletion time.

Without tombstones every merge silently **resurrects** whatever the other device deleted. This is the most commonly missed piece of the design and the bug is invisible until someone deletes something and it comes back days later. A deletion wins over a peer's edit only if its deletion time is newer.

### 3.4 Per-record history

Keep prior versions of a record inside the record, as KDBX does. When last-write-wins picks a winner, the loser is demoted to history rather than destroyed. This converts a data-loss bug into a recoverable one, and it is what makes LWW acceptable at all.

KeePass merges history entries without performing deletions on them, pruning only by configured age/count limits.

### 3.5 Moved vs edited

KDBX carries a `LocationChanged` timestamp separate from last-modified, so relocating an item and editing it merge independently. Our analogue: re-assigning a time entry to a different project is a distinct event from editing its start/stop.

### 3.6 The running timer is the real conflict case

Time entries are append-mostly and effectively immutable once stopped, so genuine conflicts are rare by construction — we are in an easier position than a password manager.

The exception, and the thing to design deliberately: **the running timer is a mutable singleton, and last-write-wins is wrong for it.** If a timer is started on the phone and another on the laptop, LWW silently discards one tracked interval — precisely the data the app exists to protect.

**Model the running timer as a per-device record keyed by a device ID.** Two devices then merge into two open intervals that the UI surfaces for reconciliation, instead of one silently winning.

### 3.7 Device-scoped settings stay out of the file — **Decided** (2026-08-13)

The generalisation of §3.6: **state that describes a device rather than the work belongs in platform preferences, not the document.** Putting it in the file subjects it to last-write-wins merge, where the loser is a setting the user deliberately chose on the other device.

The UI language is the first of these, and the test case. A Hungarian phone and an English work laptop are both legitimate for one user; a synced language would flip one device because the other changed. It is stored via `shared_preferences` as a nullable locale, where null — the default — means "follow the operating system".

This does not weaken the single-file promise, which is about *tracking data*: clients, projects, tasks, entries. Losing a device's preferences costs a re-pick; losing an entry costs recorded work. The two do not deserve the same machinery.

The boundary to apply when something new arrives: if losing it would lose recorded work, it goes in the document. If it only describes how this device presents that work, it does not. Window size, theme override and the chosen file handle all fall on the preferences side.

---

## 4. File access — **Decided**

**The abstraction is a file handed to us by the OS. Cirrhy contains no network or cloud-provider code whatsoever.**

Sync is entirely the user's business — Dropbox, iCloud Drive, Syncthing, a USB stick. This keeps the app free of OAuth clients, provider SDKs and per-vendor maintenance, and it is the direct reading of the brief.

> Considered and **rejected**: implementing our own transports. Keepass2Android ships SFTP/WebDAV/Dropbox/Drive/OneDrive/pCloud/Nextcloud clients, and Strongbox does the same on iOS, because owning the transport gives them better conflict handling than the OS route. We accept the weaker OS route in exchange for zero network code and true service neutrality. Do not re-propose WebDAV/SFTP without new information.
>
> For an OSS project there is a second reason: per-vendor SDKs need registered OAuth apps whose client secrets cannot be kept secret in a public Apache-2.0 repository.

### 4.1 The port

The entire platform surface is one narrow interface, and the core depends only on it:

- `read() -> bytes + contentHash`
- `write(bytes)` — atomic where the platform allows
- an opaque **durable handle** that survives an app restart

| Platform | Implementation |
| --- | --- |
| Linux / Windows | plain filesystem path |
| macOS | `NSOpenPanel` → **security-scoped bookmark** (`.withSecurityScope`) as the durable handle → `startAccessingSecurityScopedResource` around each access → `NSFileCoordinator` → `NSFilePresenter` while the folder is open |
| iOS | `UIDocumentPicker` → **security-scoped bookmark** as the durable handle → `startAccessingSecurityScopedResource` around each access → `NSFileCoordinator` for reads and writes → `NSFilePresenter` while the folder is open |
| Android | SAF `ACTION_OPEN_DOCUMENT_TREE` → `takePersistableUriPermission` → `ContentResolver` streams |

**macOS is an Apple platform here, not a desktop one.** Flutter's macOS template ships with App Sandbox enabled, and a sandboxed app's access to a picked folder dies with the process — the path still reads fine while the app runs, which is exactly what makes this worth stating: it looks correct until the first restart. Only a security-scoped bookmark makes the handle durable, so macOS follows iOS. Disabling the sandbox would make the path work and would also forfeit the Mac App Store; not worth it to save one file of Swift shared with iOS anyway.

### 4.2 Ask for a folder, not a file — **Decided** (2026-08-13)

Request **directory scope** at pick time rather than a single document.

With a document-scoped handle you have access to that document and nothing else — no parent directory. You therefore **cannot create a sibling temp file and rename over it**, so atomic writes become impossible on mobile and every save degrades to in-place overwrite. That is exactly the torn-write risk KeePass's file transactions exist to prevent, applied to the file holding all of the user's data.

Directory scope restores temp-then-rename and lets backups sit beside the data file. The cost is a broader-sounding permission prompt.

If a document-scoped handle is ever unavoidable, **write a backup into app-private storage immediately before each in-place overwrite**, so a torn write is always recoverable.

### 4.3 Writing

Temp file, then rename over the original — KeePass's "file transactions", which guarantee that either the original or the temp survives a failed save.

Be aware this is genuinely contentious in our exact deployment: replacing the file breaks its identity for sync clients, cloud clients holding a lock make delete-then-rename fail, and users hit real I/O errors on Google Drive/GVfs and corrupted databases on iOS Files-backed storage. Both KeePass and KeePassXC ship an option to disable it. Treat atomic-rename as the desktop default **with an escape hatch**.

**How the identity gets broken, measured** (APFS, 2026-08-15), replacing a file carrying an extended attribute:

| strategy | inode | creation date | xattrs |
| --- | --- | --- | --- |
| `Data.write(options: .atomic)` | new | lost | **lost** |
| `FileManager.replaceItemAt` | new | kept | kept |
| in-place write | same | kept | kept |

The xattr column is the one that matters, because a File Provider stamps the items it tracks. The two Apple platforms shipped `.atomic` until 2026-08-15, which means every save handed the provider an unrecognisable file at a path it thought it owned — read as delete-then-create, that leaves the provider with a brand-new local item it uploads while remote changes to the original have nowhere to land. **Writes out, nothing back**, which is precisely the iOS-against-Dropbox symptom that started §4.4's rework. They now use `replaceItemAt`, which keeps the metadata *and* this section's crash guarantee, with an in-place write as the escape hatch when the swap fails — the same fallback `PathDocumentStore` already takes. Note that neither temp-and-swap keeps the inode: what is being preserved is carried metadata, not the file object.

**Android cannot do this at all.** SAF has no replace-over-existing: `DocumentsContract.renameDocument` fails when the target name is taken, so the only sequences available are delete-then-rename or a plain in-place overwrite, and the first is strictly worse — it widens the window to include the moment when neither file exists. Android therefore writes in place, and the **app-private pre-write backup is not optional there**, it is the entire recovery story. §4.2's fallback rule, promoted to the rule.

### 4.4 Accepted failure modes

These follow from choosing the OS route. They are mitigated by the merge engine, not avoided.

- **No change notification.** Nothing tells us the file changed underneath us. Therefore: re-read and hash-compare unconditionally before every write, and on a schedule for as long as the app is in front. **Asking once, on resume, is not enough** — found 2026-08-15 against a Dropbox folder on iOS, where the app could sit days out of date while insisting it was synced. The read taken the instant the app comes forward is the one *least* likely to be fresh: a provider only starts fetching when something touches the folder and finishes seconds later, by which time the single read has been and gone. A resume-only re-read is also blind to a write that lands while the app sits open. So the reads bunch up right after a resume and then settle to a steady interval (`SessionRefresher`), with a manual pull-to-refresh and a tap-to-refresh on the status line for a sync client slower than that. This is not only about a stale screen: a stale read whose hash still matches what this device last wrote sends the next save down §3.2's "nothing else touched the file" path, which then writes over records this device never got to read. §3 is what makes the rest of it safe.

  **Partly bought back on the Apple platforms**, 2026-08-15: registering an `NSFilePresenter` for the chosen folder is the documented way to say *somebody is looking at this*, and it earns two things — the system calls back when an item under the folder changes, and a File Provider is told the item is being observed, which is the hook it is supposed to use to keep it current. So iOS and macOS re-read as the change lands rather than on the next scheduled read. It is a nudge, not a guarantee: a provider that never signals still never signals, which is why the schedule stays and this is written as an addition to it, never a replacement. The port models it as `DocumentDirectory.watch`, an empty stream everywhere it cannot be honoured — Android deliberately, because SAF's content observers are not delivered by cloud-backed providers, and Linux/Windows because `Directory.watch` there would buy the least. Our own writes are coordinated *as* the presenter, so a save never comes back as somebody else's change.
- **Stale or revoked handles.** iOS bookmarks go stale when the file is moved, renamed, or the provider app is reinstalled; Android persistable permissions can be revoked. Both must degrade to a clear "re-select your file" prompt — never a crash, never silent data loss.
- **Non-materialized files.** A provider may return a placeholder that hasn't downloaded. Coordinated access triggers the fetch, so reads are async and need a visible "downloading" state. On Android, `ContentResolver` may block or throw for cloud-backed documents.
- **Weaker conflict handling than an owned transport**, per Keepass2Android's own docs on SAF. KeePassium, which takes this same OS-provider approach on iOS, ends up advising users to enable Background App Refresh for their cloud app and to foreground it manually when files go stale. Expect to need comparable troubleshooting docs, and compensate with a robust merge plus **visibly surfaced sync state in the UI** rather than pretending sync is instant.

### 4.5 Offline

The local copy is the working copy. The app must be fully functional with no sync having happened; Keepass2Android caches in the platform's no-backup directory for exactly this. Offline correctness must never depend on the sync client having run.

### 4.6 Choosing the location — **Proposed** (2026-08-13)

The user says where the document lives. That question is asked at first run and **must stay answerable afterwards** — this is a setting with a screen, not a one-time wizard step.

**It asks for a folder, and it cannot be a path field.** Directory scope is §4.2. On mobile there is no path to type or show: SAF and `UIDocumentPicker` hand back an opaque handle, and its URI is not something to put in front of a user. The control is therefore *a button that opens the OS picker, plus the folder's display name* — on every platform, including desktop, where a path field would otherwise be tempting and would then be the one platform behaving differently.

**Pick a folder; adopt what is already in it.** If the chosen folder already holds a Cirrhy document, open and merge it rather than asking "new or existing?". Setting up the second device is then the same three taps as the first — and it is the common case, since the entire point of the choice is a folder some sync client is already watching. The filename is fixed and shown rather than asked: one user, one document (§1), and a user-chosen name would break the adoption rule for nothing.

**Changing it later is a move, not a preference write.** One flow serves three situations, and they should be built as one: first run, a deliberate move, and the forced re-pick after a handle goes stale or is revoked (§4.4). Relocating means pointing the store at the new handle and saving — read-merge-write (§3.2) already handles the case where the target holds a document, which is the case that would otherwise silently overwrite another device's history. The old file is left where it is: deleting a file inside someone's synced folder is not ours to do, and because the merge is a union, re-picking it later costs nothing.

**It is the same kind of setting as the language, and it needs the same home.** Both are device-scoped platform preferences (§3.7), both are picked once and rarely revisited, and neither belongs in the document. That makes a **preferences screen** the next screen to build: it holds the language picker — currently parked on the placeholder screen as scaffolding — and the location. First run should be that same screen in a first-run presentation rather than a separate wizard, so there is one place where either setting can be changed, one set of strings to translate, and no second implementation of the picker that drifts from the first.

**The handle is device-scoped and lives in platform preferences, never in the document** — §3.6 and §3.7, and here the argument is not even about merge semantics: an iOS security-scoped bookmark is meaningless on Linux. Two devices keeping the file in different places is normal, not a conflict. Stored beside the handle is a human-readable label, because neither a bookmark blob nor a SAF URI can be shown.

**First run asks, and the app waits for the answer.** Offering a working default instead — app-private, labelled as not synced, relocate later — was considered and dropped. It reads as the friendlier option and is worse in two concrete ways. The app-private container path is not stable across an iOS reinstall or restore, so the location chosen to be the safe temporary one is the only one that can silently move out from under the handle. And a default that is not synced quietly opts the user out of the single promise the product makes, in the one moment they were paying attention to the question. The picker is three taps; the gate is honest.

**Backups are not a second path question.** Take an automatic pre-write copy into app-private storage — §4.2's fallback rule, worth applying always rather than only when directory scope is unavailable — invisible and unasked. Beside-the-file backups exist too, but as a manual "back up now" action rather than the toggle originally sketched here — §11, which also settles what restoring one means. It does not belong on the first-run screen: asking twice before the app has been used once, for something nobody looks at until after something has gone wrong, buys a worse first launch and no safety.

---

## 5. File format — **Decided** (2026-08-14): JSON

A whole-document format loaded entirely into memory, encoded as JSON (`JsonDocumentCodec`), uncompressed.

**Avoid SQLite**, despite it being nominally a single file. WAL mode adds `-wal` and `-shm` sidecars and rollback journals add `-journal`; these break the single-file promise and corrupt the database when a sync client copies the main file without them. Whole-document also matches the merge model, since merging two SQLite files is manual work.

Size is not a concern: a heavy user generates a few thousand entries a year.

**JSON over CBOR**, settled while deciding §10. Size and speed were already immaterial at this scale; what settled it is that §10 makes the file format the product's one public seam: import is defined as "something that has never seen this codebase produces a valid document from a written spec", and §5 always valued users being able to inspect and repair their own data. Both of those are sentences about JSON. CBOR would put a binary encoder between every importing agent — and every hand repair — and the file, to save kilobytes nobody is short of. The `DocumentCodec` interface and `knownDocumentFileNames` stay: a future format change remains *possible*, it is just no longer *pending*.

---

## 6. Stack — **Decided** (2026-08-13)

**Flutter**, with the storage and merge engine as a **pure-Dart package with zero UI dependencies**, unit-tested independently of any app.

Realised as a pub workspace: `app/` (Flutter, five targets) and `packages/cirrhy_merge/` (the engine). The app depends on the engine; the engine depends on nothing but `crypto`. Built and tested against Flutter 3.44.8 / Dart 3.12.2.

Rationale:

- **Linux is both the primary dev machine and a shipping target.** Flutter treats Linux desktop as first-class (native GTK, native binary, straightforward Flatpak). Compose Desktop works but ships a JVM bundle, and Linux is visibly not JetBrains' priority.
- **The UI is simple; the logic is not.** Timer, list, forms, reports — no need for native UI precision. The difficulty is concentrated in the merge engine, which is plain code either way.
- **Solo maintainer.** One language, one toolchain, five targets.
- Licensing is clean (Flutter/Dart are BSD-3).

**Runner-up: Kotlin Multiplatform + Compose**, now stable on Android, iOS and desktop. Kotlin's sealed classes and exhaustive `when` model the merge domain — tombstones, conflict resolution, history — more precisely than Dart, though Dart 3's sealed classes and pattern matching narrowed that gap. **Choose KMP instead if** a genuinely native iOS UI is likely to matter later, since KMP allows sharing only the engine and writing SwiftUI on top.

**Ruled out:** .NET MAUI (no Linux support — disqualifying); Qt (LGPLv3 relinking obligations on mobile, plus C++ cost for a solo dev); Tauri v2 (mobile least mature of these, web-tech UI).

Friction to expect: Flutter is awkward to pin reproducibly under nix/devbox — the SDK self-updates and pulls prebuilt engine binaries. `nixpkgs` ships it; it's workable, not clean.

In Flutter, the §4 port is where essentially all platform-channel work lives — bookmark persistence on iOS, persistable URI permissions on Android. The rest is plain Dart.

---

## 7. License and naming — **Decided**

Apache License 2.0. `LICENSE` at the repo root is the verbatim upstream text and must not be edited, including the placeholder brackets in its appendix — that appendix is part of the license, not a form to fill in.

- Source files carry the standard short Apache header, `Copyright 2026 Lóránd Somogyi`. The name is spelled with accents; the ASCII `lorands` / `lorand.somogyi` in the domain and email are transliterations. Keep sources UTF-8 and pin the compiler's source encoding where it defaults to the platform charset, or the accents corrupt.
- **No `NOTICE` file, deliberately.** Apache 2.0 doesn't require one, and adding one obliges every downstream redistributor to carry it under §4(d). Add one only to carry a genuine third-party attribution.
- **Dependency licenses constrain the still-open stack.** Apache 2.0 is one-way incompatible with GPLv2, so GPLv2-only code cannot be incorporated. GPLv3/LGPLv3 are compatible. Check before adopting any framework.

Identity is rooted at the owned domain `lorands.com`, reverse-DNS: **`com.lorands.cirrhy`** — except on Apple platforms, where it is **`com.lorands.cirrhyapp`**.

| Target | Identifier |
| --- | --- |
| Android `applicationId` | `com.lorands.cirrhy` |
| Apple bundle ID (iOS + macOS) | `com.lorands.cirrhyapp` |
| JVM/Kotlin package root | `com.lorands.cirrhy` |
| Flatpak app ID + `.desktop`/metainfo | `com.lorands.Cirrhy` |

Flatpak convention capitalizes the final segment, and the app ID must match the `.desktop` and AppStream metainfo filenames exactly. **Android `applicationId` and Apple bundle IDs are permanent once published** — they cannot be changed without a new listing and the loss of the install base.

**The Apple split is scar tissue, not a preference** (2026-08-18). Apple App IDs are globally unique across *every* team, free personal teams included, and Xcode registers one silently on the first device build. Building onto an iPhone under the author's free personal team on 2026-08-14 therefore registered `com.lorands.cirrhy` to that team; the App Store listing is published under a third party's team (`docs/release/app-store.md`), which consequently could not register it, and a free personal team has no developer-portal access from which the App ID could be deleted. The choice was days of Apple Developer Support with no guaranteed outcome against a permanent change to an identifier no user ever sees. iOS and macOS moved together so the two can still share one App Store Connect record as a Universal Purchase, which requires matching bundle IDs. Android and Linux stayed: their namespaces are independent of Apple's, and moving Android's `applicationId` would orphan every installed copy to fix nothing.

> The generalizable rule, learned expensively: **never let a free personal team build a bundle ID you intend to publish under someone else's team.** Register the App ID under the publishing team first.

The method channel names did **not** follow — they remain `com.lorands.cirrhy/documents`, `/document-changes` and `/badge` on all five platforms. They are internal strings that happen to look like identity; renaming them would mean editing every platform side to change nothing observable.

Ecosystems that don't use reverse-DNS aren't bound: a Rust crate is `cirrhy`, a Go module is its repo path.

---

## 8. Open questions

1. ~~Confirm the stack (§6).~~ **Resolved 2026-08-13: Flutter.**
2. ~~**JSON vs CBOR** (§5).~~ **Resolved 2026-08-14: JSON**, settled by §10 making the file format the import seam — a spec an outside agent writes against wants a text format, and simplicity won. The `DocumentCodec` interface stays as the escape hatch.
3. **Whether to encrypt the file.** KDBX is encrypted because it holds secrets; time-tracking data may not warrant it. Encryption would complicate inspection and repair. Probably no, but decide explicitly.
4. **Timezone and DST handling** — not yet considered, and material for a time tracker. Storing UTC instants plus the originating timezone is the likely answer; entries spanning a DST transition are the test case.
5. ~~**Directory scope vs file scope** (§4.2).~~ **Resolved 2026-08-13: directory scope**, forced by the location picker (§4.6), which is the thing that asks the OS for one or the other. Atomic writes and beside-the-file backups both need a sibling temp.
6. ~~**Import from other trackers** (§10).~~ **Resolved 2026-08-14** — see §10: a one-time, agent-driven migration through the file format itself, made safe by provenance fields and batch rollback rather than by review or engine-level dedup. The remaining work there is the spec (JSON Schema + agent-facing Markdown) and the two record fields, not a decision.

## 9. First thing to build — **done** (2026-08-13)

The storage engine, standalone and headless, before any UI: record model with UUIDs and timestamps, tombstones, history, the merge function, and the read-merge-write loop. It is the part that can lose user data, it is pure logic, and it is fully testable without a running app.

The highest-value tests are the adversarial merge cases: concurrent edits to one entry, a delete racing an edit, and two devices with simultaneously running timers.

Built as `packages/cirrhy_merge`, 30 tests green. Beyond the three cases above, the merge is asserted **commutative and idempotent** — `merge(a, b) == merge(b, a)`, including on exact timestamp ties, and re-merging changes nothing. Those two properties are what make it safe to run on every save without knowing which side is "ours"; without them the result would depend on argument order.

`DocumentStore` (§4.1) is implemented on all five platforms as of 2026-08-13, together with the location picker of §4.6: a plain path on Linux and Windows, SAF with a persisted tree permission on Android, and a security-scoped bookmark on macOS and iOS. The pre-write backup is plain `dart:io` everywhere, since app-private storage is a real filesystem path even where the user's folder is not.

**Verified on Linux and, as of 2026-08-14, on an Android emulator.** The engine and the Dart half of the port are covered headless, including relocating into a folder that already holds another device's document — the case §4.6 rests on. The Android SAF path has run end to end (pick, adopt, read, write) on an API 36 emulator; its first real write surfaced a reply-encoding crash (`kotlin.Unit` is not encodable by the standard method codec — a void method must answer null), fixed in all three platform channel implementations since the Swift twins shared the bug shape. macOS and iOS have still not been built, which needs the MacBook. Treat the two Swift files as unproven until then.

Still to do: an age limit on tombstones (currently only pruned when a record outlives them) and §8.4 timezone handling, which the model sidesteps today by storing UTC instants only. Also open on the Apple side: a bookmark that resolves as stale is used as-is, because handing a refreshed handle back to Dart needs a channel shape the port does not have yet.

---

## 10. Import from other trackers — **Decided** (2026-08-14; raised 2026-08-13)

Cirrhy exists because Clockify/Toggl/Kimai were unsatisfying, so its users arrive with history in one of them. There has to be a way in.

**Cirrhy carries no per-vendor importers — and no import code at all: the seam is the file format itself.** Each vendor importer is a CSV/JSON dialect that changes without notice, for a single-user app that sees each migration once. Instead, an agent — Claude or equivalent — reads the source's export, makes the vendor-specific mapping judgements, and writes valid Cirrhy records into the live document; the ordinary read-merge-write picks them up exactly as it would another device's edits. That is one-off schema-guessing work an agent is genuinely good at, and it keeps vendor parsers out of a codebase whose merge engine is the thing that must stay trustworthy. The **embedded MCP server** alternative is rejected: a server inside an offline single-user app, against §4's no-network rule, doing a job the format already does.

The rest was settled in a design grilling on 2026-08-14. The load-bearing realisation: **one-time means one successful migration, not one attempt** — first mappings are often wrong, so the design must survive a botched run. Everything below favors *recovery* over *prevention*:

- **Import is a one-time migration, not a recurring sync.** Periodic re-import was considered and dropped; nobody migrates monthly, and designing for it (source-derived record IDs, source-derived `modified` stamps, so a re-run corrects instead of duplicates or clobbers) buys nothing the real use case needs.
- **Two provenance fields, on every record type, populated only by import:** `importSource`, a free string naming the origin (e.g. `kimai - truenas`), and `externalId`, the source's own identifier (compound if the source needs it). They exist on all record types deliberately — the mapping error that actually hurts is the client/project *hierarchy*, so the tree must be as traceable as the entries. **Neither field is a merge key.** The record `id` stays a fresh UUID, merge stays a union over UUIDs, and the engine never learns these fields mean anything: §3's invariants are untouched, and no uniqueness validation exists or should.
- **Retry protocol: tombstone the batch, re-import fresh.** Delete every record whose `importSource` matches, then run the corrected import. File-level undo (restoring a pre-import backup) is impossible by construction the moment the bad import has merged onto a second device — union-over-UUIDs merges it straight back — so rollback has to be record-level, and the tombstones are also what stop other devices resurrecting attempt one (§3.3). The agent performs the rollback through the format; zero app surface. Two caveats that belong in the spec: rollback takes with it any hand-edits made to imported records (a tombstone kills the record's history too), so verify an import before editing what it brought in; and rollback rides on tombstones, so §9's still-open tombstone age limit bounds how long a rolled-back batch stays dead for a long-offline device.
- **No review-before-merge.** The agent writes straight into the live file; review is post-hoc, in the app. What is worth reviewing is the dozen-line client/project mapping, never the 3,000 entries, and batch rollback is the undo. A staging step would add surface without adding protection recoverability doesn't already give — for a single user, the same eyes review on every device.
- **Enforcement is recoverability, not validation.** The agent is *prescribed* — not engine-enforced — to stamp the provenance fields. Prompt compliance would be an unacceptable guard against silent corruption; it is an acceptable guard when the failure is visible and the recovery is cheap.

**The deliverable is the spec, more than any code**: it only works if the format and entity model are specified well enough for something that has never seen this codebase to produce a valid document. Concretely, two artifacts, versioned with `packages/cirrhy_merge` and kept in step with it:

- a **JSON Schema** for the document format, so an importer can machine-validate its output before writing;
- an **agent-facing Markdown spec** (llms-file style): the entity model (clients → projects → tasks, entries, tombstones, per-device running timers), the field and timestamp rules an importer must respect, the provenance-field rules, and the retry protocol above.

Built 2026-08-14: the fields live on every record type in `packages/cirrhy_merge` (formatVersion 2 — a v1 reader would silently strip them, the exact lossy write-back the version gate exists to refuse), and the two documents live in `packages/cirrhy_merge/doc/` (`cirrhy-document.schema.json`, `llms.md`). A schema-sync test in the package compares the schema's field lists against what the codec actually emits, so the spec cannot drift from the code unnoticed.

---

## 11. Backups and archiving — **Decided** (2026-08-15)

Settled in a design grilling on 2026-08-15 that started from an archive proposal and ended somewhere smaller and sounder. The through-line: **every file-level manipulation of history is defeated by our own merge engine.** §2's "this cannot be solved at the file layer" applies to the app's maintenance features exactly as it applies to sync clients.

**Manual backup — Decided.** A user-triggered action copies the committed document to `cirrhy-backup-YYYY-MM-DD.json` beside it (directory scope, §4.2, is what makes the sibling write possible). Mechanics:

- The copy is the **on-disk bytes after the commit queue has flushed** — a snapshot of what is durably true, never a re-serialization of in-memory state.
- A second backup on the same day gets a `-2`, `-3` suffix rather than overwriting: overwriting would silently destroy a snapshot the user deliberately took.
- Backup files are **inert to the app**: never in `knownDocumentFileNames`, never adopted by the §4.6 rule, never read, and **never deleted**. The app writes backups and touches nothing else in the user's folder.
- The natural moment for one is immediately before an agent-driven import (§10): the backup is then the record-level recovery source for anything batch rollback doesn't cover.

**Restore is record-level, through the format — Decided.** A backup is a *source document*, not a rollback button. Recovery means opening the backup and writing the destroyed records back into the live document with **fresh `modified` timestamps**, so they out-date the tombstones or bad edits that killed them and every device converges through ordinary merge — §10's rollback protocol run in reverse, zero coordination, zero app surface; an agent job through the format, like import itself.

> Considered and **rejected: restore by copying a backup over `cirrhy.json`.** It only works if every device stays silent until sync has fully propagated — a distributed protocol no user can execute (the phone in a pocket, the laptop in a drawer), and the file layer is exactly where §2 says coordination is unsolvable. The failure mode is the bad kind: the restore visibly succeeds, then days later an offline device's newer tombstones merge back in and the restored records silently die again, long after anyone remembers why. Never document file-copy restore as a recovery procedure.

> Considered and **rejected: archiving old records into a second file** (move everything before a date to `cirrhy-archive.json`). Without tombstones, the next save from any device that still holds the records resurrects all of them (§3.3) — an archive that undoes itself in a day. With tombstones, the live file keeps a permanent tombstone per archived record, and §9's still-open tombstone age limit becomes a resurrection deadline: one device offline longer than the limit merges the *entire archived history* back, silently. The archive file itself would sit outside read-merge-write and be blind-written — a second live document with none of the machinery that makes the first one safe. And reports would stop seeing archived periods, when reporting over an arbitrary timespan is first-class (§1). All of that to shrink a file §5 already establishes never gets big enough to matter. If old entries ever clutter the UI, the fix is a date filter in queries, not a storage feature.

Built 2026-08-15, with no platform code at all: the §4.1 channel was already generic over file names, so the port only grew a `existingFiles(names)` query and a named-sibling variant of `storeAt`. `DocumentSession.backUpNow()` runs on the commit queue (which is what delivers the flushed-bytes promise), and the settings screen's Data folder section carries the button. Covered headless in `document_session_backup_test.dart` and at the widget level in `settings_screen_test.dart`.

> Considered and **rejected: automatic backups on a schedule with keep-N retention** (`cirrhy-automatic-backup-YYYY-MM-DD.json`). Retention makes the app delete files from the user's synced folder — the line §4.6 deliberately refuses to cross, here crossed silently on a timer with every deletion propagated by the sync client. Worse, two devices on the same schedule blind-write the same filename; the sync client resolves that collision by renaming one to a conflict name the retention pattern no longer matches, so the folder accumulates undeletable sediment while retention prunes only the tidy names — unbounded growth caused by the feature meant to bound it. Making it safe needs per-device filenames plus the app pattern-deleting its own artifacts, which is real machinery serving a need the every-save app-private backup (§4.6) and the sync service's own versioning (Dropbox history, Syncthing versioning) already cover.

---

## 12. Reporting beyond the app — **Decided** (2026-08-15)

§1 makes reporting over an arbitrary timespan first-class, and the Reports screen carries that: day/week/month/custom ranges, filters, summary and list views. What Cirrhy deliberately does **not** carry is a report *builder* — pivot tables, chart designers, export-format pickers. That surface grows without bound (every answered question breeds the next checkbox), every export format is a dialect, and it is the same shape of work §10 already identified: one-off judgement over a well-specified format, which is an agent job, not app code. **The file format is the reporting seam exactly as it is the import seam** — the §10 artifacts (`cirrhy-document.schema.json` for shape, `llms.md` for meaning) are already the complete contract, and reporting is the easier direction: read-only, so none of import's rollback machinery is even needed.

Two deliverables make the claim concrete rather than aspirational (built 2026-08-15):

- **A packaged skill, `.claude/skills/cirrhy-report`**, bundling verbatim copies of the schema and the agent guide plus the semantics a correct report needs and the schema cannot express (durations from `start`/`stop`, UTC→local bucketing, tombstones and `history` excluded from totals, `archived` ≠ deleted, per-entry `billable` authoritative). With it, a conversation needs only the user's `cirrhy.json` and the question. A sync test in `packages/cirrhy_merge` (`skill_sync_test.dart`) keeps the bundled copies byte-identical to `doc/` — the same drift-tether pattern as §10's schema-sync test, with `doc/` canonical.
- **A full-size example document plus worked examples, `docs/reporting/`**: a generated, deterministic `cirrhy.json` (21 months, ~1,400 entries, an imported era with provenance, history, tombstones — `tool/gen_example_document.py`), and three prompt→artifact pairs (two charts, one spreadsheet) produced from nothing but the file and the quoted prompt. An engine test (`example_document_test.dart`) keeps the example decodable and in the codec's canonical byte form, so the "any agent can work this file" claim is never demonstrated on a document the app itself would not produce.

Reporting through the seam is **read-only by prescription**, the same enforcement philosophy as §10: the skill and the guide say never to write the document for a reporting task, and if an agent ignores that, §3's read-merge-write and the recovery story bound the damage — prescription plus recoverability, not validation.

---

## References

- [KeePass — Synchronization](https://keepass.info/help/v2/sync.html)
- [KDBX XML spec — `DeletedObjects`, `LocationChanged`](https://github.com/keepassxreboot/keepassxc-specs/blob/master/kdbx-xml/rfc.md)
- [Keepass2Android — file handling](https://github.com/PhilippC/keepass2android/wiki/Keepass2Android-file-handling)
- [KeePassXC — atomic save vs. cloud sync](https://github.com/keepassxreboot/keepassxc/discussions/13050)
- [Strongbox — KeePassXC saves breaking iOS Files-based databases](https://strongbox.reamaze.com/kb/troubleshooting-and-errors/my-ios-files-based-database-breaks-or-does-not-load-after-i-change-it-with-keepassxc)
- [KeePassium — SFTP/FTP sync](https://support.keepassium.com/kb/sync-sftp/)
- [Kotlin Multiplatform vs Flutter (JetBrains)](https://kotlinlang.org/docs/multiplatform/kotlin-multiplatform-flutter.html)
