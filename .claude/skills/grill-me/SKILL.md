---
name: grill-me
description: Adversarially interrogate the user's design decisions to find weak reasoning before it becomes code. Use when the user asks to be grilled, challenged, or pushed on their thinking, wants assumptions stress-tested, or wants to close out open questions in DESIGN.md. Takes an optional topic (e.g. "grill me on storage").
---

# Grill me

Interrogate the user's decisions. The goal is to find the reasoning that does not hold up **while it is still free to change** — before it is code, a published bundle ID, or a file format users have data in.

This is not a review of code. It is a review of *thinking*.

## Before asking anything

Read `DESIGN.md` and `CLAUDE.md`. Decisions there are tagged **Decided**, **Proposed**, or **Open**. If the user gave a topic, scope to it; otherwise choose targets yourself.

## What to target, in priority order

1. **Irreversible decisions.** Cost of being wrong is what matters, not how interesting the question is. In this project: Apple bundle IDs and Android `applicationId` are permanent once published; the on-disk format becomes a migration burden the moment real data exists; merge semantics can lose data silently and unrecoverably.
2. **Decisions tagged Proposed that are being treated as settled.** Drift from "I suggested this" to "we decided this" is the most common way an unexamined choice ships.
3. **Open questions being deferred past the point where they are cheap.** §4.2 directory-vs-file scope has to be settled before the picker is built, not after.
4. **Load-bearing assumptions nobody has stated.** Especially assumptions about how users actually behave, which are usually guesses wearing a confident tone.
5. **Decisions justified by aesthetics or familiarity** rather than by the constraint they are supposed to serve.

## How to grill

**One question at a time. Wait for the answer.** A list of ten questions gets one shallow reply and teaches nothing. A single sharp question gets a real answer.

Make each question concrete and answerable. "Have you considered scalability?" is worthless. "Two devices are both offline for a week and both edited the same entry — which one does the user see, and how do they find out the other existed?" forces a real answer.

**Prefer scenarios to abstractions.** Name specific inputs, specific sequences, specific users. The fastest way to expose a hole is to walk a concrete case through the design until it breaks.

**Push back once on a weak answer, then move on.** If the answer is hand-waving, say what specifically is unconvincing and ask again. If it is still weak, note it as unresolved and go to the next target — do not badger. The user's time is the scarce resource.

**Accept good answers visibly and move on.** If the reasoning holds, say so plainly and go to the next thing. A grilling where nothing can pass is theatre, and the user will stop trusting the exercise.

**Argue the strongest version of the opposing case,** not a weak one you can knock down. If you cannot construct a serious case against a decision, that decision is probably fine — say so instead of manufacturing doubt.

**Do not be contrarian for sport.** Every question should have a plausible answer that would change what gets built. If the answer changes nothing, it is not worth asking.

## Fair game

- "What breaks if this assumption is false?"
- "What would have to be true for the alternative to win?"
- "Who else solved this, and what did they do differently? Why were they wrong — or were they?"
- "What is the cost of being wrong here, and when does it become unrecoverable?"
- "Is this solving a problem you have, or one you imagine having?"
- "You rejected X earlier. Has anything changed since that would flip it?"

## Closing the loop

A grilling that changes no artifact was a conversation, not work. At the end:

- Update `DESIGN.md` where answers settled something: retag **Open** → **Decided**, or **Proposed** → **Decided**, and record the *reasoning*, not just the verdict.
- Add any new open question the grilling exposed to §8.
- Where a rejection was reaffirmed, record it as an explicit rejection with its reason so it does not get re-proposed later.
- Where an answer was weak and stayed weak, say so plainly rather than recording it as settled.

Report what changed and what remains unresolved.
