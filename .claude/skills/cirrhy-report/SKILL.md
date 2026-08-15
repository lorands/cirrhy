---
name: cirrhy-report
description: Analyze, report on, chart, summarize, or export data from a Cirrhy time-tracking document (cirrhy.json) — totals, timesheets, invoicing backup, spreadsheets, visualizations — or safely modify one (imports, batch edits, rollbacks). Use whenever the user points at a cirrhy.json or asks questions about their tracked time. Needs only the file and the question; the format contract is bundled.
---

# Working with a Cirrhy document

All of a Cirrhy user's tracking data lives in one JSON file, `cirrhy.json`.
Ask for its path if the user has not given one. The bundled contract is
complete — never guess at the format:

- [`references/cirrhy-document.schema.json`](references/cirrhy-document.schema.json)
  — authoritative for **shape**: collections, fields, types, timestamps.
- [`references/llms.md`](references/llms.md) — authoritative for **meaning**,
  and for the rules any *write* must follow.

The hierarchy is clients → projects → tasks, with time entries referencing a
project and optionally a task; every level above an entry may be null.

## Reporting is read-only

A reporting task never writes the document — compute from a copy in memory
and put outputs (charts, spreadsheets, summaries) in separate files the user
names. Only touch `cirrhy.json` itself when the user explicitly asks for a
change, and then follow `references/llms.md` to the letter: read-merge-write,
fresh UUID v4 ids, provenance stamps, tombstones for deletions, validate
against the schema before writing back.

## Semantics that make a report correct

- **Duration is `stop − start`, per entry.** A null `stop` is a timer still
  running on some device: report it separately as in-progress, never fold a
  guessed duration into totals.
- **All timestamps are UTC instants.** Bucketing by day/week/month is only
  meaningful after converting to the user's timezone — confirm which one, and
  state it on every output.
- **Ignore `tombstones`** (those records are deleted). A file the app wrote
  never holds a record and its tombstone at once; if some other writer left
  both, resolve as the merge engine would — the tombstone deletes the record
  only if its `deletedAt` is newer than the record's `modified`. And **ignore
  `history`** (prior versions of the record it sits inside; counting them
  double-counts). The current top-level fields are the truth.
- **`runningTimers` are live device timers**, not entries — mention them,
  don't total them.
- **`archived` is a display flag, not deletion**: entries of archived
  projects still count in the periods they were worked. Don't silently drop
  them.
- **`billable` on the entry is authoritative** — projects carry a default,
  entries can differ. Bill from the entry's flag.
- **Null hierarchy levels get an explicit bucket** — "(no project)",
  "(no client)" — never silently dropped, never merged into a real one.
- **`importSource`/`externalId` are provenance**, useful as filters ("only
  the Kimai batch"), never as identity — `id` is the only key.

## Outputs

State the filters on every artifact: date range, timezone, billable-only or
not, which clients/projects. Cross-check any exported totals by recomputing
them a second way (per-entry sum vs. group sum). Format dates, times and
durations for the user's locale — `1.5 h`, `1,5 óra` and `1,5 Std.` differ by
more than the decimal mark.
