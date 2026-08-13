# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

Greenfield. The repository contains only `init.md` (the product brief), this file, and `LICENSE` — no source, no build system, no git history yet. There is no stack chosen. Do not assume a language, framework, or toolchain; confirm with the user before scaffolding one, then replace this section with real build/test/run commands.

## What Cirrhy is

A personal time tracker (name = **Circadian Rhythm**), built out of frustration with Clockify/Toggl/Kimai. Take their feature set, strip the team dimension, keep it simple.

Product constraints that drive nearly every design decision:

- **Single-user, not teams.** No accounts, no sharing, no permissions model. Anything that implies multi-user is out of scope.
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

Still **Proposed, not confirmed**: the stack (Flutter, with the merge engine as a pure-Dart package), and JSON vs CBOR. Confirm with the user before scaffolding either.

## License and naming

Apache 2.0; identity is rooted at `com.lorands.cirrhy`. Full detail in `DESIGN.md` §7. Day-to-day rules:

- New source files get the standard short Apache header, `Copyright 2026 Lóránd Somogyi` — accented. The ASCII `lorands`/`lorand.somogyi` in the domain and email are transliterations, not the name. Keep sources UTF-8.
- `LICENSE` is verbatim upstream text; never edit it, including its appendix placeholders.
- No `NOTICE` file, deliberately — adding one obliges every downstream redistributor under §4(d).
- Apache 2.0 cannot incorporate **GPLv2-only** code. Check any dependency's license before proposing it.

## Environment

- Linux Manjaro is the primary dev machine; a MacBook Pro is also available (needed for iOS builds).
- Containers via **podman**, not docker. `docker` commands generally work as `podman` equivalents, but write scripts against podman.
- **nix** and **devbox** are both in use — prefer declaring toolchain deps there over ad-hoc system installs.
- Penpot (design/mockups) with MCP is self-hosted at http://192.168.50.138:31027/ — check it for design intent before inventing UI.
