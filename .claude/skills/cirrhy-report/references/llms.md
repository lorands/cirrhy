<!--
Copyright 2026 Lóránd Somogyi

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->

# Importing data into Cirrhy — a guide for agents

You are reading this because someone wants their time-tracking history moved
from another tracker (Kimai, Clockify, Toggl, a CSV, anything) into Cirrhy.
Cirrhy ships no importers on purpose: **you** do the vendor-specific mapping,
and this document plus [`cirrhy-document.schema.json`](cirrhy-document.schema.json)
are the complete contract for doing it safely. If you follow the rules below,
a botched import is fully recoverable; if you skip them, it is not.

## The file

All of a user's data lives in **one JSON file, `cirrhy.json`**, in a folder
the user chose (typically inside Dropbox/Syncthing/Nextcloud — the file is
synced between the user's devices by whatever service they use; Cirrhy itself
has no network code). Ask the user where their `cirrhy.json` is.

The app survives concurrent edits: on every save it re-reads the file and
merges, record by record. So you write to the live file directly — there is
no import mode, no staging area, no app restart needed. A running app picks
your records up on its next refresh exactly as it would another device's.

## The one loop you must follow

1. **Read** the current `cirrhy.json`. If it does not parse as JSON, stop and
   tell the user — never overwrite a file you could not read.
2. **Add** your records to its collections. Never remove or modify anything
   that was already there, and never touch records lacking your
   `importSource` (exception: the rollback protocol below).
3. **Validate** the result against `cirrhy-document.schema.json`.
4. **Write** the whole document back — ideally to a temp file in the same
   folder, then rename over `cirrhy.json`.

If the write races an app save, nothing is lost either way: the app's next
save merges your version with its own. But re-reading immediately before
writing keeps the window small.

## The document

```json
{
  "format": "cirrhy",
  "formatVersion": 2,
  "clients":       [ ... ],
  "projects":      [ ... ],
  "tasks":         [ ... ],
  "entries":       [ ... ],
  "runningTimers": [ ... ],
  "tombstones":    [ ... ]
}
```

The hierarchy is **clients → projects → tasks**, with **time entries**
referencing a project and optionally a task. Every level above an entry is
optional: an entry may have `projectId: null`, a project may have
`clientId: null`. `runningTimers` are live timers, one per device;
`tombstones` are recorded deletions. Exact field lists, types and timestamp
formats are in the schema; the schema is authoritative for shape, this file
for meaning.

Semantics the schema cannot express:

- **Timestamps are UTC instants** (`2026-08-14T09:30:00.000Z`). If the source
  exports local times, convert using the timezone the user confirms — do not
  guess silently.
- **`modified`** is when the record last changed. For an import, the time you
  run is fine. **`locationChanged`** (projects, tasks, entries): set it equal
  to `modified` on records you create.
- **`start` and `stop` are one unit.** Never invent one to match the other:
  an entry whose duration you had to guess is worse than an entry skipped
  with a note to the user.
- **References must resolve within the document you write**: every
  `clientId`, `projectId`, `taskId` you emit names a record that exists after
  your import (yours or a pre-existing one). A `taskId` must belong to the
  entry's `projectId`.

## Rules for imported records

1. **`id` is a fresh UUID v4 for every record you create.** Never derive it
   from, or reuse, a source system's identifier.
2. **Stamp provenance on every record you create**, entries and hierarchy
   alike:
   - `importSource`: one string for the whole migration, identical on every
     record of the batch — name the system and instance, e.g.
     `"kimai - truenas"`. If the user re-imports from the same source later,
     reuse the same string only when the runs are meant to be one batch.
   - `externalId`: the record's identifier in the source. Compound it
     yourself if the source needs more than one value (`"project:7/task:12"`)
     — the encoding is yours, just keep it stable and documented in your
     summary to the user.
3. **Only closed entries.** Every entry you write has a non-null `stop`.
   **Never create `runningTimers`** — a running timer belongs to a live
   device, and an imported one would demand reconciliation on every device
   the user owns.
4. **No `history` on imported records** — they have no past. Omit the key.
5. **Write `formatVersion: 2`.** The provenance fields you stamp *are* v2
   fields, so the document you produce is v2 even when the file you read
   said 1 — and the schema requires the constant. Refuse to proceed if the
   file's version is *greater* than 2: a newer app wrote it and you would
   strip fields you do not know about; ask the user for an updated copy of
   this guide instead. **Warn the user when you upgrade a v1 file**: app
   builds older than v2 will refuse the document afterwards — deliberately,
   fail-closed, no data touched — until every device runs a v2 build.

## Mapping the source

Vendor models differ; the judgement is yours, but make it reviewable:

- Toggl/Clockify *clients* and Kimai *customers* → Cirrhy **clients**;
  their *projects* → **projects**. Toggl *tags* and Clockify *tags* have no
  Cirrhy equivalent — fold the useful ones into entry descriptions or drop
  them, and say which you did.
- Sources with no task level: leave `taskId` null rather than manufacturing
  tasks.
- **Before writing, show the user the mapping table** — every source
  client/project/task and what it becomes, a dozen lines, not three thousand
  entries. After writing, summarize: N clients, N projects, N tasks,
  N entries, batch name, anything skipped and why.

## If the import was wrong: rollback and retry

To undo batch `X` completely:

1. Remove every record whose `importSource` is `X` from its collection.
2. For **each** removed record, append a tombstone
   `{ "id": "<that record's id>", "deletedAt": "<now, UTC>" }`.
3. Write the document back (same loop as above).

The tombstones are not optional: without them, any other device that already
synced the batch will merge it straight back. To retry, roll back and then
import fresh — new UUIDs are fine, the old ones are dead.

**Warn the user before rolling back**: edits they made to imported records
die with the batch. That is why an import should be verified (and if
necessary redone) *before* they start editing what it brought in.

## How merge decides — enough to reason about safety

Per record `id`: newer `modified` wins; the loser is kept inside the winner's
`history`. A tombstone beats a record only if its `deletedAt` is newer than
the record's `modified` — and an edit newer than the tombstone revives the
record. Merge is commutative and idempotent, which is why the app can merge
on every save and why your write is safe to repeat. Full rationale:
`DESIGN.md` §3 and §10 in the repository root.

## Worked example (one client, one project, one entry)

```json
{
  "format": "cirrhy",
  "formatVersion": 2,
  "clients": [
    {
      "id": "6f1e63e2-4a09-4c1a-9d5e-2b7a0c9f4d11",
      "modified": "2026-08-14T10:00:00.000Z",
      "name": "Acme Corp",
      "archived": false,
      "importSource": "kimai - truenas",
      "externalId": "customer:3"
    }
  ],
  "projects": [
    {
      "id": "a2b9d0f4-7c31-49e8-b6aa-9e0d1c2f3a55",
      "modified": "2026-08-14T10:00:00.000Z",
      "locationChanged": "2026-08-14T10:00:00.000Z",
      "name": "Website",
      "clientId": "6f1e63e2-4a09-4c1a-9d5e-2b7a0c9f4d11",
      "color": null,
      "billable": true,
      "archived": false,
      "importSource": "kimai - truenas",
      "externalId": "project:7"
    }
  ],
  "tasks": [],
  "entries": [
    {
      "id": "c3d4e5f6-1a2b-4c3d-8e9f-0a1b2c3d4e66",
      "modified": "2026-08-14T10:00:00.000Z",
      "locationChanged": "2026-08-14T10:00:00.000Z",
      "start": "2026-08-10T08:30:00.000Z",
      "stop": "2026-08-10T10:15:00.000Z",
      "projectId": "a2b9d0f4-7c31-49e8-b6aa-9e0d1c2f3a55",
      "taskId": null,
      "description": "Landing page copy",
      "billable": true,
      "importSource": "kimai - truenas",
      "externalId": "timesheet:1842"
    }
  ],
  "runningTimers": [],
  "tombstones": []
}
```

(That is a complete, valid document — a real import merges its records into
whatever the user's file already holds instead of starting from empty.)
