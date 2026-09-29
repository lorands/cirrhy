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

"""Builds the document the store screenshots are taken against.

Source is docs/reporting/cirrhy.json — the same generated example the
reporting docs use, so the screenshots and the worked report examples show one
consistent fictional consultancy rather than two.

Two things are done to it, both for the same reason: a screenshot has to look
like a Wednesday afternoon, not like an archive.

1. Every timestamp is shifted so the newest *entry* ended two hours ago. The
   anchor is deliberately the newest entry stop rather than the newest
   timestamp of any kind — `modified` fields run later than the work they
   describe, and anchoring on those leaves the most recent entry days in the
   past, which is exactly what the Timer screen's recent list would show.

2. A running timer is added for the screenshot device. The main screen is the
   running timer plus recent work, and a screenshot of an idle 00:00:00 sells
   the wrong thing.

Nothing here is committed: the output is a throwaway consumed by
tool/gen_screenshots.sh. Regenerate rather than keeping one around, or the
dates drift back into the past.
"""

import datetime as dt
import json
import re
import sys
from pathlib import Path

# Matches the device.id the capture seeds into preferences, so the running
# timer belongs to *this* device and renders as the user's own rather than as
# a foreign timer awaiting reconciliation.
DEVICE_ID = "4f1c2a90-7b3e-4d55-9c81-0a6e2f3b8d41"

# Meridian Labs › Telemetry Platform › Query API. Chosen for the length of the
# names as much as anything: long enough to look real, short enough not to
# ellipsize on a phone.
RUNNING = {
    "project": "43aad3db",
    "task": "480ee62d",
    "description": "Cursor pagination for the query API",
    "minutes_ago": 47,
}

STAMP = re.compile(r'"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3})Z"')


def iso(moment: dt.datetime) -> str:
    return moment.strftime("%Y-%m-%dT%H:%M:%S.") + f"{moment.microsecond // 1000:03d}Z"


def full_id(document: dict, kind: str, prefix: str) -> str:
    for record in document[kind]:
        if record["id"].startswith(prefix):
            return record["id"]
    raise SystemExit(f"no {kind[:-1]} starting {prefix} in the example document")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: gen_screenshot_seed.py <source.json> <out.json>")
    source, out = Path(sys.argv[1]), Path(sys.argv[2])

    document = json.loads(source.read_text())
    raw = json.dumps(document)

    newest = max(
        dt.datetime.fromisoformat(entry["stop"].replace("Z", "+00:00"))
        for entry in document["entries"]
        if entry.get("stop")
    )
    now = dt.datetime.now(dt.timezone.utc)
    delta = (now - dt.timedelta(hours=2)) - newest

    def shift(match: re.Match) -> str:
        moment = dt.datetime.fromisoformat(match.group(1) + "+00:00") + delta
        return '"' + iso(moment) + '"'

    document = json.loads(STAMP.sub(shift, raw))

    started = now - dt.timedelta(minutes=RUNNING["minutes_ago"])
    document["runningTimers"] = [
        {
            # id equals deviceId: the running timer is keyed by device, one
            # per device (§3.6).
            "id": DEVICE_ID,
            "deviceId": DEVICE_ID,
            "modified": iso(started),
            "startedAt": iso(started),
            "projectId": full_id(document, "projects", RUNNING["project"]),
            "taskId": full_id(document, "tasks", RUNNING["task"]),
            "description": RUNNING["description"],
        }
    ]

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(document, indent=2))

    print(f"    shifted {delta.days} days · running timer {RUNNING['minutes_ago']}m in")


if __name__ == "__main__":
    main()
