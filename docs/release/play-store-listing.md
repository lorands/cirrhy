# Play Store listing copy

Everything the Play Console asks for, ready to paste. The runbook that walks
through where each of these fields lives is [`play-store.md`](play-store.md).

> **Metadata rules, before you write anything of your own.** Google's are
> nearly the inverse of Apple's, so do not paste between the two listings
> without reading this. Apple's Guideline 2.3.10 forbids naming other *mobile*
> platforms, which is why [`app-store-listing.md`](app-store-listing.md) never
> says "Android"; **Google has no such rule**, and the copy below names every
> platform Cirrhy runs on, because on this store that is a feature and not a
> risk. What Google *does* police is the title and the description's tone: no
> emoji, no ALL-CAPS blocks, no "free" in the title, no "#1" or "best" claims,
> and no keyword stuffing. The App Store description's shouted section headers
> are therefore Title Case here.

## Store settings

| Field | Value |
|---|---|
| App name | `Cirrhy: Time Tracker` *(20 / 30)* |
| Default language | English (United States) |
| App or game | App |
| Free or paid | **Free** — and this one is a one-way door; a free app cannot be switched to paid later |
| Application ID | `com.lorands.cirrhy` — permanent from the first upload |
| Category | Productivity |
| Tags | Play's list is fixed, five maximum. The closest matches are *Time management*, *Personal organiser*, *Business tools*. Pick from what the Console actually offers rather than from this line. |
| Contact email | `lorand.somogyi@appific.app` — publicly displayed on the listing |
| Contact website | `https://github.com/lorands/cirrhy` |
| Contact phone | Optional; leave blank |
| External marketing | Off — nothing to promote to |

The app name carries a descriptor here where the App Store's is bare `Cirrhy`,
and the difference is deliberate: Apple gives you a separate 100-character
keywords field, Google does not, so on Play the title is doing search work that
Apple's keywords field does elsewhere. If the publisher would rather keep brand
naming identical across both stores, plain `Cirrhy` is a legitimate choice —
just make it consciously, because the title is editable but re-indexing after a
change is not instant.

## Short description

*The line under the title in search results and at the top of the listing.
(74 / 80)*

```
Time tracking in a single file you own. No account, no server, no network.
```

## Full description

*(2326 / 4000)*

```
Cirrhy is a personal time tracker that keeps everything in a single file you own.

No account. No server. No network code at all — the release build does not even ask Android for the internet permission, so there is nothing to shut down, breach, or paywall between you and your own hours.

What It Does

• A running timer on the main screen, above your recent work. Every past entry has a run button that starts a new timer from it — one tap to pick up where you left off.
• Clients, projects and tasks, with colours per project and billable flags.
• Reports over a day, a week, a month or any range you choose: summary charts, per-project totals, or the raw entry list.
• Light and dark, following the system or set per device.
• Five languages: English, magyar, español, italiano, Deutsch.

One File, And It Is Yours

Everything Cirrhy knows lives in one readable JSON document, in a folder you pick. Choosing that folder is the first and only thing Cirrhy asks you to set up. You can open the file, back it up, script it, or walk away with it entirely — there is no export feature because there is nothing to export it from.

Sync Is Your Choice

Put that folder inside whatever you already trust — Google Drive, Dropbox, Nextcloud, Syncthing — and point every device at it. Cirrhy talks to none of them; it just uses the file they carry. That is what lets it work with all of them, and what lets it keep working if any of them changes its mind.

Built To Be Merged, Not Overwritten

Two devices edited between syncs is the normal case here, not an error to complain about:

• Saving reads what is currently on disk and merges into it, never blindly overwrites.
• Merging happens per record rather than per file, so nothing is lost to whoever saved last.
• The loser of a conflicting edit is demoted into that record's history, not destroyed.
• Deletions leave tombstones, so a merge can never resurrect something you deleted.
• The running timer is per device — two timers left running surface for you to reconcile, instead of one silently swallowing the other.

Open Source

Apache 2.0. The entire source, including every line that touches your data, is public at github.com/lorands/cirrhy, auditable by anyone — including you.

Also available for iPhone, iPad, Mac, Windows and Linux. The same file works on all of them.
```

The second paragraph's claim about the internet permission is deliberately
falsifiable, and it is true of the shipping build:
`app/test/android_manifest_test.dart` asserts it, and any user can check it
against the installed app. Do not soften it into "we don't use the network" —
the specific version is the one worth making, and it is the same fact the Data
safety section below rests on.

## Graphics

All generated, never hand-made — the same rule the app icons follow.

| Asset | Requirement | Source |
|---|---|---|
| App icon | 512×512, 32-bit PNG, ≤1024 KB | `assets/icon/play-store-512.png` |
| Feature graphic | 1024×500, 24-bit PNG, **no alpha** | `assets/icon/play-feature-graphic.png` |
| Phone screenshots | 2–8, 320–3840px a side, at most 2∶1 | `tool/gen_screenshots.sh --phone` |
| Tablet screenshots | 4+, 1080–7680px a side, at most 2∶1 | `tool/gen_screenshots.sh --tablet` |

```sh
python3 tool/gen_app_icons.py        # both graphics
tool/gen_screenshots.sh --android    # both screenshot sets
```

Do **not** reuse `docs/screenshots/` — that is the README set at 1080×2400,
which is 2.22∶1 and over Play's aspect cap. It would be refused. The AVDs that
produce a legal set are in [`play-store.md`](play-store.md).

The feature graphic carries no text on purpose: Play overlays the app title
over it in some placements and crops the sides in others, and typesetting the
name would make the file depend on which fonts the generating machine has.

## Store listing translations

Play builds the listing's advertised language list from the **store listing
translations** you add in the Console, and from nothing in the bundle. So the
app ships five languages whether or not you translate anything here, and the
store page claims one until you do.

Untranslated is a legitimate starting point — the app still installs and still
switches languages. Adding them later costs a Console edit and no release.
Priority order if they are added: **hu** first (the author's own language and
the one with users to gain), then de, es, it. Each needs the title, short
description, full description, and ideally its own screenshot set:

```sh
tool/gen_screenshots.sh --android --locale hu
```

## App content

Answer these in the Console's **App content** section. Every one of them is
required before a production release.

| Declaration | Answer |
|---|---|
| Privacy policy URL | `https://github.com/lorands/cirrhy/blob/main/docs/legal/privacy-policy.md` |
| App access | All functionality is available without special access |
| Ads | No, this app does not contain ads |
| Content rating | Category *Utility, Productivity, Communication or Other*; every question **No** |
| Target audience | **18 and over** only |
| News app | No |
| Government app | No |
| Financial features | None of these |
| Health apps | No |
| Advertising ID | No, this app does not use advertising ID |
| Data safety | No data collected, no data shared — see below |

Two of these deserve their reasoning written down, because a future release
will be asked them again by someone who was not here:

**Target audience — 18 and over.** Not because Cirrhy is unsuitable for anyone
younger, but because declaring any band under 18 pulls the app into Google's
Families policy and its extra obligations. A billable-hours tracker has no
claim on being designed for children, so the honest answer is also the cheap
one.

**App access — no special access.** True: Cirrhy has no accounts, no login and
no demo credentials, so there is nothing for a reviewer to be let into. What
there *is* — and what Play gives you nowhere to explain — is that the app gates
every screen behind choosing a folder on first launch. On the App Store that
needed a paragraph of review notes to avoid being read as a broken app. If a
Play rejection ever cites it, this is the appeal:

```
Cirrhy requires no account, login, or credentials of any kind.

On first launch the app asks the user to choose a folder before anything else. This is intentional and is the app's core design, not an error state: the app stores all of a user's data in a single file inside a folder they control, so that they can place it inside whatever file-sync service they already use. Choosing that folder is therefore the first thing the app must ask, and there is deliberately no default location.

Tap the folder button and pick any location in the system folder picker — creating a new folder in Documents is fine. The app is fully usable immediately afterwards.

The app makes no network requests of any kind. The release build does not request the INTERNET permission, and contains no networking code, no accounts, no analytics, and no third-party data collection.
```

### Data safety, in full

The whole form is the same answer, so it is short: **the app collects no user
data and shares none.**

- *Does your app collect or share any of the required user data types?* **No.**
- Every data category — location, personal info, financial info, health,
  messages, photos, files, calendar, contacts, app activity, web browsing, app
  info and performance, device or other IDs — **not collected, not shared**.
- The follow-up questions about encryption in transit, deletion requests, and
  independent security review do not apply, because they are only asked of
  collected data.

The evidence, in the order a reviewer would want it: the release build requests
no `INTERNET` permission, so no data can leave the device by any route; there
is no analytics, crash-reporting or advertising SDK in the dependency list; and
the per-device identifier that appears in the user's own document is a **random
UUID minted on first run**, not a hardware, advertising or account identifier,
and it never leaves that file. The reasoning at the length a lawyer would want
it is in [`docs/legal/privacy-policy.md`](../legal/privacy-policy.md).

## Countries and pricing

Free, all countries and regions. There is no reason to restrict availability
for an app that contacts no servers and therefore has no per-region cost,
latency or legal surface. Revisit only if a specific jurisdiction's rules make
the listing itself a problem.

## What's new

*For the first release. (196 / 500)*

```
First Play Store release.

Cirrhy has been in daily use and tested on Android, Linux, iPhone, iPad and Mac. Reports of anything that looks wrong are very welcome — github.com/lorands/cirrhy/issues
```

## Before submitting

The legal pages are complete — publisher (Appific Kft.) and contact address
(<lorand.somogyi@appific.app>) are both filled in, and the privacy policy
covers the Play listing alongside the App Store one. Per release, the things
that actually change are:

1. **The screenshots.** Regenerate rather than reuse; the seed anchors the
   newest entry two hours ago, so a kept set shows a stale week.
2. **The *What's new* text**, which is per release and per language.
3. **The version**, if you are shipping something other than the current
   `app/pubspec.yaml` version — and note that `versionCode` must increase on
   every upload, including one that is never released. `tool/release.sh`
   handles that; a hand-built bundle does not.
