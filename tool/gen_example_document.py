#!/usr/bin/env python3
# Copyright 2026 Lóránd Somogyi
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Regenerates the example document, docs/reporting/cirrhy.json.

The file is generated, never hand-edited — the same rule as the app icons.
Everything is derived from one seeded RNG and fixed dates, so re-running the
script reproduces the file byte for byte; change the constants below and
re-run rather than editing the JSON.

The document tells a story a reporting prompt can bite into: a solo
freelancer, November 2024 through August 2026, three clients plus internal
work. The shape mirrors what a real file accumulates:

  - The first eight months were imported from Kimai in one batch, so every
    record from that era carries `importSource`/`externalId` — the same
    provenance an agent-driven import (doc/llms.md) stamps.
  - A few records were edited after creation, so they carry `history` (prior
    versions demoted by read-merge-write, newest first). One project was
    renamed, one client and two projects archived when the work ended.
  - Deletions left `tombstones` whose records are gone from the collections —
    which is exactly how a live file looks after a delete has merged.
  - `runningTimers` is empty: a document at rest, no device mid-timer.

Workdays follow a believable rhythm: Budapest office hours (stored as UTC
instants like every Cirrhy timestamp), a lunch gap, Hungarian public
holidays, vacations, sick days, the occasional Saturday of open-source work.
"""

from __future__ import annotations

import datetime as dt
import json
import random
import sys
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = REPO_ROOT / "docs" / "reporting" / "cirrhy.json"

rng = random.Random(20260815)

FIRST_DAY = dt.date(2024, 11, 4)
LAST_DAY = dt.date(2026, 8, 14)

# Everything strictly before this date came over from Kimai, in one batch.
IMPORT_CUTOVER = dt.date(2025, 7, 5)
IMPORT_RUN = dt.datetime(2025, 7, 5, 17, 42, 0)
IMPORT_SOURCE = "kimai - home server"

VACATIONS = [
    (dt.date(2024, 12, 23), dt.date(2025, 1, 3)),
    (dt.date(2025, 4, 14), dt.date(2025, 4, 18)),
    (dt.date(2025, 8, 4), dt.date(2025, 8, 15)),
    (dt.date(2025, 12, 22), dt.date(2026, 1, 2)),
    (dt.date(2026, 7, 13), dt.date(2026, 7, 24)),
]

HOLIDAYS = {  # Hungarian public holidays falling on weekdays in the span
    dt.date(2024, 12, 25), dt.date(2024, 12, 26), dt.date(2025, 1, 1),
    dt.date(2025, 4, 18), dt.date(2025, 4, 21), dt.date(2025, 5, 1),
    dt.date(2025, 6, 9), dt.date(2025, 8, 20), dt.date(2025, 10, 23),
    dt.date(2025, 12, 25), dt.date(2025, 12, 26), dt.date(2026, 1, 1),
    dt.date(2026, 4, 3), dt.date(2026, 4, 6), dt.date(2026, 5, 1),
    dt.date(2026, 5, 25),
}


def uuid4() -> str:
    return str(uuid.UUID(int=rng.getrandbits(128), version=4))


def ts(t: dt.datetime) -> str:
    return t.strftime("%Y-%m-%dT%H:%M:%S") + ".000Z"


# ---------------------------------------------------------------- hierarchy

CLIENTS = {
    "meridian": {"name": "Meridian Labs", "externalId": "customer:2"},
    "kavics": {"name": "Kavics Studio", "externalId": "customer:3"},
    "aster": {"name": "Aster & Voss", "externalId": "customer:5",
              "archivedOn": dt.datetime(2026, 4, 2, 8, 15, 0)},
}

PROJECTS = {
    "telemetry": {
        "name": "Telemetry Platform", "client": "meridian", "color": "#2F6FBF",
        "billable": True, "from": FIRST_DAY, "to": None,
        "externalId": "project:11",
        "tasks": {
            "Ingest pipeline": "activity:31", "Query API": "activity:32",
            "Dashboard": "activity:33", "Alerting": "activity:34",
            "Reviews & meetings": "activity:35",
        },
    },
    "mobile": {
        "name": "Mobile companion", "client": "meridian", "color": "#7A5FC7",
        "billable": True, "from": dt.date(2025, 9, 15), "to": None,
        "tasks": {"Prototype": None, "Sync layer": None, "Release prep": None},
    },
    "relaunch": {
        "name": "Website relaunch", "client": "kavics", "color": "#C75F8A",
        "billable": True, "from": dt.date(2025, 2, 10),
        "to": dt.date(2025, 11, 28), "externalId": "project:14",
        "importedName": "Website refresh",
        "renamedOn": dt.datetime(2025, 9, 3, 9, 20, 0),
        "archivedOn": dt.datetime(2025, 12, 5, 10, 5, 0),
        "tasks": {
            "Design system": "activity:41", "CMS templates": "activity:42",
            "Content migration": "activity:43", "Launch support": "activity:44",
        },
    },
    "microsites": {
        "name": "Brand microsites", "client": "kavics", "color": "#C7873F",
        "billable": True, "from": dt.date(2026, 1, 12), "to": None,
        "tasks": {"Campaign pages": None, "Analytics": None},
    },
    "migration": {
        "name": "Data migration", "client": "aster", "color": "#3FA7A0",
        "billable": True, "from": FIRST_DAY, "to": dt.date(2026, 3, 31),
        "externalId": "project:9",
        "archivedOn": dt.datetime(2026, 4, 2, 8, 16, 0),
        "tasks": {
            "Schema mapping": "activity:21", "ETL jobs": "activity:22",
            "Cutover rehearsal": "activity:23",
        },
    },
    "oss": {
        "name": "Open source", "client": None, "color": "#6B8F3F",
        "billable": False, "from": FIRST_DAY, "to": None,
        "externalId": "project:17",
        "tasks": {"Maintenance": "activity:51", "Issue triage": "activity:52"},
    },
    "admin": {
        "name": "Admin", "client": None, "color": None,
        "billable": False, "from": FIRST_DAY, "to": None,
        "externalId": "project:5",
        "tasks": {"Invoicing": "activity:11", "Bookkeeping": "activity:12",
                  "Planning": "activity:13"},
    },
}

DESCRIPTIONS = {
    "telemetry": {
        "Ingest pipeline": [
            "Kafka consumer backpressure fix", "Batch compaction tuning",
            "Schema registry upgrade", "Dead-letter queue handling",
            "Ingest lag alert follow-up", "Partition rebalancing test",
        ],
        "Query API": [
            "Aggregation endpoint pagination", "Query planner edge cases",
            "Rate limiting middleware", "p95 latency profiling",
            "OpenAPI spec cleanup", "API contract review",
        ],
        "Dashboard": [
            "Chart panel virtualization", "Dashboard filter state bug",
            "New retention widget", "Empty-state designs",
            "Cross-filter interactions",
        ],
        "Alerting": [
            "Threshold rule editor", "Alert dedup logic",
            "PagerDuty webhook integration", "Silence windows",
        ],
        "Reviews & meetings": [
            "Sprint planning", "PR reviews", "Weekly sync with Meridian",
            "Architecture review", "Retro", "Backlog grooming",
        ],
        None: ["Support rotation", "Incident follow-up", "Platform misc"],
    },
    "mobile": {
        "Prototype": [
            "Navigation skeleton", "Auth flow spike",
            "Offline cache experiment", "Design review with Meridian",
        ],
        "Sync layer": [
            "Delta sync protocol", "Conflict handling tests",
            "Background fetch scheduling", "Push token lifecycle",
        ],
        "Release prep": [
            "TestFlight build & notes", "Play Console listing",
            "Crash triage", "Release checklist",
        ],
        None: ["Mobile standup", "Device lab testing"],
    },
    "relaunch": {
        "Design system": [
            "Token mapping from Figma", "Typography scale",
            "Component library setup", "Dark mode palette",
        ],
        "CMS templates": [
            "Article template", "Landing page blocks",
            "Preview environment", "Editor permissions",
        ],
        "Content migration": [
            "Legacy export scripts", "Redirect map",
            "Image optimization pass", "Content QA",
        ],
        "Launch support": [
            "DNS cutover", "Perf budget check",
            "Launch-day monitoring", "Post-launch fixes",
        ],
        None: ["Relaunch call with Kavics"],
    },
    "microsites": {
        "Campaign pages": [
            "Spring campaign page build", "A/B variant setup",
            "Hero animation", "Form handling",
        ],
        "Analytics": [
            "Event taxonomy", "Consent banner tuning", "Funnel dashboards",
        ],
        None: ["Microsites planning with Kavics"],
    },
    "migration": {
        "Schema mapping": [
            "Customer table mapping", "Field-level mapping review",
            "Nullable edge cases", "Mapping doc update",
        ],
        "ETL jobs": [
            "Nightly ETL run fixes", "Dedup pass", "Throughput tuning",
            "Error report tooling",
        ],
        "Cutover rehearsal": [
            "Dry-run walkthrough", "Rollback drill",
            "Checksum verification", "Cutover runbook",
        ],
        None: ["Migration status call"],
    },
    "oss": {
        "Maintenance": [
            "Dependency bumps", "CI matrix fix", "Docs typos & examples",
            "Cutting a patch release",
        ],
        "Issue triage": ["Weekly issue triage", "Repro attempts", "Label cleanup"],
        None: ["OSS misc"],
    },
    "admin": {
        "Invoicing": ["Monthly invoices", "Chasing a late payment",
                      "Quote for Kavics"],
        "Bookkeeping": ["Receipts & VAT", "Quarterly tax filing",
                        "Bank reconciliation"],
        "Planning": ["Week planning", "Pipeline review", "Portfolio update"],
        None: ["Email & admin"],
    },
}

NO_PROJECT_DESCRIPTIONS = [
    "Call with the accountant", "New laptop setup",
    "Backup & NAS maintenance", "Conference talk prep",
]

EDIT_SUFFIXES = [" — incl. standup", " (scope revised)", " + follow-up notes"]


def project_weight(key: str, day: dt.date) -> float:
    p = PROJECTS[key]
    if day < p["from"] or (p["to"] is not None and day > p["to"]):
        return 0.0
    if key == "telemetry":
        return 4.0 if day >= dt.date(2025, 9, 15) else 5.0
    if key == "mobile":
        return 3.0
    if key == "relaunch":
        return 3.0
    if key == "microsites":
        return 2.0
    if key == "migration":
        return 1.5 if day >= dt.date(2026, 1, 1) else 3.0
    if key == "oss":
        return 0.8
    return 0.7  # admin


def on_vacation(day: dt.date) -> bool:
    return any(a <= day <= b for a, b in VACATIONS)


# ------------------------------------------------------------ record builders

client_ids = {k: uuid4() for k in CLIENTS}
project_ids = {k: uuid4() for k in PROJECTS}
task_ids = {(pk, tn): uuid4() for pk, p in PROJECTS.items() for tn in p["tasks"]}


def demote(rec: dict) -> dict:
    """A record as it appears inside history: modified plus the payload.

    Mirrors RecordVersion in records.dart — no id, no locationChanged,
    no nested history.
    """
    return {"modified": rec["modified"]} | {
        k: v for k, v in rec.items()
        if k not in ("id", "modified", "locationChanged", "history")}


def client_record(key: str) -> dict:
    c = CLIENTS[key]
    created = ts(IMPORT_RUN)
    rec = {"id": client_ids[key], "modified": created, "name": c["name"],
           "archived": False, "importSource": IMPORT_SOURCE,
           "externalId": c["externalId"]}
    if "archivedOn" in c:
        prior = demote(rec)
        rec = {**rec, "modified": ts(c["archivedOn"]), "archived": True,
               "history": [prior]}
    return rec


def project_record(key: str) -> dict:
    p = PROJECTS[key]
    was_imported = "externalId" in p
    created = IMPORT_RUN if was_imported else dt.datetime.combine(
        p["from"], dt.time(8, 30))
    rec = {
        "id": project_ids[key], "modified": ts(created),
        "locationChanged": ts(created),
        "name": p.get("importedName", p["name"]),
        "clientId": client_ids[p["client"]] if p["client"] else None,
        "color": p["color"], "billable": p["billable"], "archived": False,
    }
    if was_imported:
        rec |= {"importSource": IMPORT_SOURCE, "externalId": p["externalId"]}
    history: list[dict] = []
    if "renamedOn" in p:
        history.insert(0, demote(rec))
        rec = {**rec, "modified": ts(p["renamedOn"]), "name": p["name"]}
    if "archivedOn" in p:
        history.insert(0, demote(rec))
        rec = {**rec, "modified": ts(p["archivedOn"]), "archived": True}
    if history:
        rec["history"] = history
    return rec


def task_record(pk: str, name: str) -> dict:
    p = PROJECTS[pk]
    ext = p["tasks"][name]
    created = IMPORT_RUN if ext else dt.datetime.combine(
        p["from"], dt.time(8, 35))
    rec = {"id": task_ids[(pk, name)], "modified": ts(created),
           "locationChanged": ts(created), "name": name,
           "projectId": project_ids[pk], "archived": False}
    if ext:
        rec |= {"importSource": IMPORT_SOURCE, "externalId": ext}
    return rec


# ---------------------------------------------------------------- the days

def pick_project(day: dt.date, saturday: bool) -> str:
    keys = list(PROJECTS)
    weights = [project_weight(k, day) for k in keys]
    if saturday:  # weekend work skews heavily to the hobby project
        weights = [w * (5.0 if k == "oss" else 1.0)
                   for k, w in zip(keys, weights)]
    return rng.choices(keys, weights)[0]


def make_entry(start: dt.datetime, minutes: int, day: dt.date,
               saturday: bool) -> dict:
    stop = start + dt.timedelta(minutes=minutes, seconds=rng.randrange(60))
    if rng.random() < 0.015:
        project, task, desc, billable = None, None, rng.choice(
            NO_PROJECT_DESCRIPTIONS), False
    else:
        pk = pick_project(day, saturday)
        names = list(PROJECTS[pk]["tasks"])
        task_name = rng.choice(names) if rng.random() < 0.82 else None
        project = project_ids[pk]
        task = task_ids[(pk, task_name)] if task_name else None
        desc = rng.choice(DESCRIPTIONS[pk][task_name])
        billable = PROJECTS[pk]["billable"] and rng.random() >= 0.03
    modified = stop + dt.timedelta(seconds=rng.randrange(20, 90))
    return {"id": uuid4(), "modified": ts(modified), "locationChanged":
            ts(modified), "start": ts(start), "stop": ts(stop),
            "projectId": project, "taskId": task, "description": desc,
            "billable": billable}


entries: list[dict] = []
day = FIRST_DAY
sick_days = 0
while day <= LAST_DAY:
    weekday = day.weekday()
    workday = (weekday < 5 and not on_vacation(day) and day not in HOLIDAYS)
    if workday and rng.random() < 0.045:
        workday, sick_days = False, sick_days + 1
    saturday = weekday == 5 and not on_vacation(day) and rng.random() < 0.07
    if workday:
        n = rng.choice([2, 3, 3, 4, 4, 5])
        cursor = dt.datetime.combine(day, dt.time(6, 50)) + dt.timedelta(
            minutes=rng.randrange(100))
        lunch_after = rng.choice([1, 2])
        for i in range(n):
            if cursor.time() > dt.time(16, 45):
                break
            minutes = int(rng.triangular(30, 180, 70))
            e = make_entry(cursor, minutes, day, saturday=False)
            entries.append(e)
            gap = rng.randrange(5, 35)
            if i == lunch_after:
                gap += rng.randrange(35, 70)
            cursor = dt.datetime.strptime(
                e["stop"], "%Y-%m-%dT%H:%M:%S.000Z") + dt.timedelta(
                minutes=gap)
    elif saturday:
        cursor = dt.datetime.combine(day, dt.time(8, 30)) + dt.timedelta(
            minutes=rng.randrange(90))
        for _ in range(rng.choice([1, 1, 2])):
            minutes = int(rng.triangular(40, 150, 80))
            e = make_entry(cursor, minutes, day, saturday=True)
            entries.append(e)
            cursor = dt.datetime.strptime(
                e["stop"], "%Y-%m-%dT%H:%M:%S.000Z") + dt.timedelta(
                minutes=rng.randrange(20, 50))
    day += dt.timedelta(days=1)

# Stamp import provenance on the Kimai-era entries, ids in export order.
timesheet_id = 1000
for e in entries:
    if e["start"] < IMPORT_CUTOVER.isoformat():
        e["modified"] = ts(IMPORT_RUN)
        e["locationChanged"] = ts(IMPORT_RUN)
        e["importSource"] = IMPORT_SOURCE
        e["externalId"] = f"timesheet:{timesheet_id}"
        timesheet_id += 1

# A few native entries were touched up later; the prior version is demoted
# into history by read-merge-write, exactly as the app does it.
for e in entries:
    if "importSource" in e or rng.random() >= 0.025:
        continue
    prior = demote(e)
    edited = dt.datetime.strptime(
        e["modified"], "%Y-%m-%dT%H:%M:%S.000Z") + dt.timedelta(
        hours=rng.randrange(2, 72))
    e["modified"] = ts(edited)
    if rng.random() < 0.55:
        stop = dt.datetime.strptime(
            e["stop"], "%Y-%m-%dT%H:%M:%S.000Z") + dt.timedelta(
            minutes=rng.randrange(5, 25))
        e["start"], e["stop"] = e["start"], ts(stop)  # one unit, together
    else:
        e["description"] = e["description"] + rng.choice(EDIT_SUFFIXES)
    e["history"] = [prior]

tombstones = [
    {"id": uuid4(),
     "deletedAt": ts(IMPORT_RUN + dt.timedelta(
         days=rng.randrange(3, 390), minutes=rng.randrange(600)))}
    for _ in range(12)]


def by_id(records: list[dict]) -> list[dict]:
    # The codec writes every collection sorted by id; match its canonical
    # form so decode → encode reproduces this file byte for byte.
    return sorted(records, key=lambda r: r["id"])


document = {
    "format": "cirrhy",
    "formatVersion": 2,
    "clients": by_id([client_record(k) for k in CLIENTS]),
    "projects": by_id([project_record(k) for k in PROJECTS]),
    "tasks": by_id([task_record(pk, tn) for pk, p in PROJECTS.items()
                    for tn in p["tasks"]]),
    "entries": by_id(entries),
    "runningTimers": [],
    "tombstones": by_id(tombstones),
}

OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
OUT_PATH.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n",
                    encoding="utf-8")

hours = sum(
    (dt.datetime.strptime(e["stop"], "%Y-%m-%dT%H:%M:%S.000Z")
     - dt.datetime.strptime(e["start"], "%Y-%m-%dT%H:%M:%S.000Z"))
    .total_seconds() for e in entries) / 3600
print(f"{OUT_PATH.relative_to(REPO_ROOT)}: "
      f"{len(entries)} entries, {hours:,.0f} h tracked, "
      f"{timesheet_id - 1000} imported, {sick_days} sick days, "
      f"{OUT_PATH.stat().st_size / 1024:.0f} KiB", file=sys.stderr)
