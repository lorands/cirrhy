# App Store listing copy

Everything App Store Connect asks for, ready to paste. Fill the three
bracketed placeholders before submitting.

> **Metadata trap, before you write anything of your own:** App Review
> Guideline 2.3.10 forbids naming other *mobile* platforms in your metadata.
> The README's "five platforms — Linux, Android, Windows, macOS, iOS" line
> therefore cannot be pasted here. Desktop platforms are fine to mention;
> **Android is not.** The copy below is already written around this.

## App information

| Field | Value |
|---|---|
| Name | `Cirrhy` |
| Subtitle | `Time tracking in one file` *(25 / 30)* |
| Bundle ID | `com.lorands.cirrhyapp` |
| SKU | `cirrhy` |
| Primary language | English (U.S.) |
| Primary category | Productivity |
| Secondary category | Business |
| Copyright | `2026 Lóránd Somogyi` |
| Age rating | 4+ — every questionnaire answer is *None* |
| Privacy Policy URL | `https://github.com/lorands/cirrhy/blob/main/docs/legal/privacy-policy.md` |
| Support URL | `https://github.com/lorands/cirrhy/blob/main/docs/legal/support.md` |
| Marketing URL | `https://github.com/lorands/cirrhy` |

## Promotional text

*Editable without shipping a new build — use it for what is currently true.*
*(138 / 170)*

```
Free and open source, and it stays that way. No account, no server, no network
code — your hours live in one file, in a folder you choose.
```

## Keywords

*Comma-separated, no spaces. Do not repeat the app name or the category — those
are already indexed. (94 / 100)*

```
time,tracker,timesheet,timer,freelance,billable,hours,offline,private,invoice,worklog,projects
```

## Description

```
Cirrhy is a personal time tracker that keeps everything in a single file you own.

No account. No server. No network code at all — nothing to shut down, breach, or paywall between you and your own hours.

WHAT IT DOES

• A running timer on the main screen, above your recent work. Every past entry has a run button that starts a new timer from it — one tap to pick up where you left off.
• Clients, projects and tasks, with colours per project and billable flags.
• Reports over a day, a week, a month or any range you choose: summary charts, per-project totals, or the raw entry list.
• Light and dark, following the system or set per device.
• Five languages: English, magyar, español, italiano, Deutsch.

ONE FILE, AND IT IS YOURS

Everything Cirrhy knows lives in one readable JSON document in a folder you pick. You can open it, back it up, script it, or walk away with it entirely. There is no export feature because there is nothing to export it from.

SYNC IS YOUR CHOICE

Put that folder inside whatever you already trust — iCloud Drive, Dropbox, Nextcloud, Syncthing — and point every device at it. Cirrhy talks to none of them; it just uses the file they carry. That is what lets it work with all of them, and what lets it keep working if any of them changes its mind.

BUILT TO BE MERGED, NOT OVERWRITTEN

Two devices edited between syncs is the normal case here, not an error to complain about:

• Saving reads what is currently on disk and merges into it, never blindly overwrites.
• Merging happens per record rather than per file, so nothing is lost to whoever saved last.
• The loser of a conflicting edit is demoted into that record's history, not destroyed.
• Deletions leave tombstones, so a merge can never resurrect something you deleted.
• The running timer is per device — two timers left running surface for you to reconcile, instead of one silently swallowing the other.

OPEN SOURCE

Apache 2.0. The entire source, including every line that touches your data, is public at github.com/lorands/cirrhy, auditable by anyone — including you.

Also available for Mac, Windows and Linux.
```

## What's New in This Version

*For the first submission:*

```
First App Store release.

Cirrhy has been in daily use and tested on iPhone, iPad, Mac and Linux. Reports of anything that looks wrong are very welcome — github.com/lorands/cirrhy/issues
```

## App Review notes

*This one matters more than it looks. Cirrhy gates the whole app behind picking
a folder, and a reviewer who does not know that reads it as a broken app and
rejects under Guideline 2.1.*

```
No account, login, or demo credentials are needed — Cirrhy has no accounts at all.

FIRST LAUNCH: the app asks you to choose a folder before it will do anything else. This is intentional and is the app's core design, not an error state. Tap the folder button and pick any location in the Files picker — "On My iPhone" is fine, or create a new folder there. The app becomes fully usable immediately afterwards.

There is deliberately no default location: the app stores all of a user's data in a single file inside a folder they control, so that they can place it inside whatever file-sync service they already use. Choosing that folder is therefore the first thing the app must ask.

The app makes no network requests of any kind. It contains no networking code, no accounts, no analytics, and no third-party data collection.
```

## App Privacy (nutrition label)

Answer: **Data Not Collected.**

Every category is *No*. The app has no network code, so no data can leave the
device by any route. The reasoning, in the detail a reviewer might ask for, is
in [`docs/legal/privacy-policy.md`](../legal/privacy-policy.md). Note in
particular that the per-device identifier in the document is a **random UUID
minted on first run** — not a hardware, advertising, or account identifier —
and never leaves the user's own file.

App Tracking Transparency: not applicable, nothing is tracked and no
`NSUserTrackingUsageDescription` is present.

## Export compliance

Answer **No** to "Does your app use encryption?"

Cirrhy makes no network connections and implements no encryption. It uses
SHA-256 to detect whether the document on disk has changed — hashing, not
encryption. Once `ITSAppUsesNonExemptEncryption` is set to `false` in
`Info.plist`, App Store Connect stops asking this per upload.

## Screenshots

Required for the sizes Apple currently mandates: **iPhone 6.9"**, and
**iPad 13"** for as long as `TARGETED_DEVICE_FAMILY` stays `"1,2"`.

`docs/screenshots/` already holds the README set, but those are the wrong
dimensions for the store. Capture fresh ones from the simulator — Timer,
Reports, Projects, and the entry editor, in that order, since the first two are
what appears without scrolling on the product page.

## Before submitting

The legal pages are complete — publisher (Appific Kft.) and contact address
(<lorand.somogyi@appific.app>) are both filled in. The only thing left to
adjust per release is the version number in *What's New*, if you ship
something other than the current `app/pubspec.yaml` version.
