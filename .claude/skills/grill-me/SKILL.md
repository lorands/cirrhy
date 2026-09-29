---
name: grill-me
description: Adversarially interrogate the user's design decisions on Cirrhy to find weak reasoning before it costs data, a store listing, or a migration. Use when the user asks to be grilled, challenged, or pushed on their thinking ("grillezz meg", "kérdezz ki"), wants assumptions stress-tested, or wants to close out open questions in DESIGN.md. Takes an optional topic (e.g. "grill me on timezones", "grill me on the release").
---

# Grill me

Interrogate the user's decisions. The goal is to find the reasoning that does not hold up **while it is still cheap to change**.

This is not a code review, it is a review of *thinking*. But Cirrhy is no longer a design on paper. It ships (tagged releases, App Store and Play listings through Appific Kft.), and users' `cirrhy.json` files already exist in synced folders. So "cheap to change" now has three price levels, and a question is worth asking in proportion to the price:

| Price | What lives there | Why |
| --- | --- | --- |
| **Permanent** | Android `applicationId` `com.lorands.cirrhy`, Apple bundle ID `com.lorands.cirrhyapp`, anything a published store declaration asserts (Play Data safety, the privacy policy's "no `INTERNET`" claim) | Changing it means a new listing and losing the install base, or a false public statement. DESIGN.md §7 records the time this already went wrong once. |
| **Migration** | The on-disk format (`formatVersion`, record fields, the JSON Schema in `packages/cirrhy_merge/doc/`), merge semantics, tombstone rules | Real files exist on devices that update on different days. A mistake here loses data silently or strands a device. |
| **Refactor** | UI, screens, the refresh schedule, tooling | Only costs work. Grill it only when the reasoning is poor, not just because it is changeable. |

## Before asking anything

Build today's map yourself, because DESIGN.md goes stale in places:

1. Read `DESIGN.md` and `CLAUDE.md`. Decisions are tagged **Decided**, **Proposed** or **Open**.
2. Collect what is actually open. That means DESIGN.md §8, plus the "Still to do" / "Not built yet" sentences scattered through DESIGN.md §9 and CLAUDE.md, which never got a §8 number.
3. **Check the tags against the code.** A section tagged **Proposed** that is fully built is the drift this skill exists to catch (at the time of writing, §4.6 is one). The same goes for a status line that contradicts the repo (DESIGN.md's header still says nothing is implemented). Read the relevant code or tests before claiming either way, because a claim about the code you have not checked is exactly the hand-waving this skill is supposed to catch.
4. For store-shaped topics, read the relevant runbook in `docs/release/` first. The two stores differ in ways that look interchangeable and are not.

If the user gave a topic, scope to it. Otherwise pick targets yourself and say in one line which ones and why.

## What to target, in priority order

1. **Permanent and migration-priced decisions** (the table above). In this project that concretely means:
   - **Version skew between devices.** One user, several devices, one file, each device updating on its own day. The codec refuses a `formatVersion` newer than it understands. What does the user on the not-yet-updated phone actually see, and is that the intended experience? What happens to a new record field when an older build does read-merge-write?
   - **Anything the engine's invariants rest on**: commutativity, idempotence, tombstones beating edits only when newer, never field-merging a time entry, per-device running timers. A proposal that weakens one of these has to say which test would now fail and why that is acceptable.
   - **Store declarations and the binary drifting apart.** A new dependency or permission that would make the privacy policy, Data safety or App Privacy answers false.
2. **Proposed decisions being treated as settled**, including the ones already in code. Drift from "I suggested this" to "we built it" is how an unexamined choice ships.
3. **Open questions being deferred past the point where they are cheap.** Timezone/DST (§8.4) gets more expensive with every entry recorded as a bare UTC instant. Encryption (§8.3) is free to decide now and expensive after a user's file is on a shared drive. Tombstone age limits grow the file forever until they are decided.
4. **Load-bearing assumptions nobody has stated**, especially about how users actually behave with sync clients: how long a device stays offline, whether the user ever opens the file by hand, whether they have two folders. These are usually guesses wearing a confident tone. The Dropbox-on-iOS staleness found on 2026-08-15 (DESIGN.md §4.4) is the model case of one of these turning out false.
5. **Decisions justified by aesthetics or familiarity** rather than by the constraint they serve: single user, single file, five targets, no network code.

## Settled rejections

DESIGN.md and CLAUDE.md record explicit rejections: network/cloud-provider clients (WebDAV, SFTP, Dropbox), SQLite, a default document location, file-level restore, archiving to a second file, the language or folder choice in the document, a toolchain manager, CBOR. **Do not re-raise these as if they were fresh.** They are fair game in exactly one form: "You rejected X because Y. Has Y changed?" If you can name what changed, ask. If you can't, leave it alone.

## How to grill

**Speak the user's language.** If they write in Hungarian, grill in Hungarian. Artifacts stay in English (see closing the loop).

**One question at a time. Wait for the answer.** A list of ten questions gets one shallow reply and teaches nothing. A single sharp question gets a real answer. Use plain prose, not a multiple-choice widget: the point is to hear the reasoning, not to pick an option.

**Prefer scenarios to abstractions, and make them Cirrhy scenarios.** "Have you considered edge cases?" is worthless. These force a real answer:

- "The laptop is on v0.3 and wrote `formatVersion` 3. The phone is still on v0.2.3 because the Play rollout is staged. The user opens the phone to start a timer. What happens, second by second?"
- "An entry runs from 01:30 to 03:30 on the night the clocks go back in Budapest. How long does the report say it was, and in which timezone does it appear on the laptop that the user carried to Lisbon?"
- "Two devices both edited the same entry while offline for a week. Which one wins, where does the loser go, and how does the user ever find out it existed?"

Walk the case through the actual design, and where it matters the actual code, until it holds or breaks.

**Push back once on a weak answer, then move on.** Say specifically what is unconvincing and ask again. If it is still weak, note it as unresolved and go to the next target without badgering. The user's time is the scarce resource.

**Accept good answers visibly and move on.** If the reasoning holds, say so plainly. A grilling where nothing can pass is theatre, and the user will stop trusting the exercise.

**Argue the strongest version of the opposing case.** Clockify, Toggl, Kimai, KeePassium and Keepass2Android are the real prior art here (DESIGN.md cites them). If one of them made a different choice for a reason that applies, bring it. If you cannot construct a serious case against a decision, it is probably fine. Say so instead of manufacturing doubt.

**Do not be contrarian for sport.** Every question should have a plausible answer that would change what gets built, written or declared. If the answer changes nothing, don't ask it.

## Fair game

- "What breaks if this assumption is false, and would anyone notice before data was lost?"
- "Which test would catch this going wrong? If none, why not?"
- "What would have to be true for the alternative to win?"
- "What is the cost of being wrong here, and at which release does it become unrecoverable?"
- "Is this solving a problem you have, or one a team tracker has?" (Single-user is a constraint, not a gap.)
- "You rejected X on <date>. Has anything changed since that would flip it?"

## Closing the loop

A grilling that changes no artifact was a conversation, not work. At the end:

- **DESIGN.md** (English, dated with absolute dates such as `2026-09-24`):
  - Where answers settled something, retag **Open** → **Decided** or **Proposed** → **Decided**. Record the *reasoning*, not just the verdict, in the style of the existing sections: the constraint it serves and the alternative it beat.
  - Add each new open question to §8 with the next free number. Strike resolved items through with `~~…~~` and a **Resolved <date>** note rather than deleting them; that is the convention §8 already uses.
  - Record reaffirmed rejections explicitly, with their reason, so they are not re-proposed later.
  - Fix any stale tag or status line the pre-read turned up.
- **CLAUDE.md** restates the non-negotiables. If one of those changed, update that summary too. Otherwise leave CLAUDE.md alone: it is not supposed to duplicate DESIGN.md.
- If a decision changes the format, the work is not done until `packages/cirrhy_merge/doc/` (schema and `llms.md`), the copies in `.claude/skills/cirrhy-report/`, and the example document from `tool/gen_example_document.py` are all in step. The sync tests will fail otherwise, so say that this follow-up is needed rather than leaving it implied.
- Where an answer was weak and stayed weak, say so plainly. Do not record it as settled.

Do not commit. Report what changed, what remains unresolved, and which follow-up work the decisions imply.
