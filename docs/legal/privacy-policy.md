# Cirrhy Privacy Policy

**Effective 18 August 2026.** Applies to the Cirrhy application on iOS, iPadOS,
macOS, Android, Linux and Windows.

**Short version: Cirrhy collects nothing.** There is no account, no server, and
no network code in the app. Everything it knows is a file in a folder you chose,
on devices you own. Neither the developer nor the publisher receives any of it,
because there is no mechanism by which we could.

## What Cirrhy stores, and where

### Your document

One human-readable JSON file, `cirrhy.json`, in the folder you pick on first
run. It holds the data you enter — clients, projects, tasks, time entries — plus
three things the merge engine needs to keep several devices consistent:

- **Per-record history**, so the loser of a conflicting edit is demoted rather
  than destroyed.
- **Tombstones** — the identifier and deletion time of records you deleted — so
  that syncing with a device that has not seen the deletion cannot resurrect
  them.
- **A running-timer record per device**, keyed by a device identifier.

That device identifier is a **random UUID minted on first run**. It is not
derived from hardware, an advertising identifier, an account, a phone number, or
anything else that identifies you or your device to anyone. It exists so that a
timer running on your laptop and a timer running on your phone do not overwrite
each other. Because it lives in the shared document, other devices reading that
same document can see it — which is the entire point of it.

### Device preferences

Four settings are stored by the operating system's own preference store, on the
device, and deliberately **not** in the document — a phone and a work laptop are
allowed to disagree about them:

| Key | What it holds |
|---|---|
| `settings.documentLocation` | The handle for your chosen folder, and a readable label for it |
| `settings.locale` | Your language override, if you set one |
| `settings.themeMode` | Light, dark, or follow the system |
| `device.id` | The random UUID described above |

### Backups

Before writes that cannot be made atomic, and whenever you press **Back up now**,
Cirrhy copies your document into app-private storage on that device. These
copies never leave the device, and are removed when you uninstall the app.

## What Cirrhy does not do

- **No network requests.** Not to us, not to anyone. The app contains no
  networking code at all. On Android this is externally checkable: the release
  manifest requests no `INTERNET` permission. (Debug and profile builds do
  request it, because Flutter's hot reload runs over a socket. Store builds are
  release builds.)
- **No accounts, no sign-in, no identity of any kind.**
- **No analytics, telemetry, crash reporting, or usage measurement.**
- **No advertising, and no tracking as the App Tracking Transparency framework
  defines it.** Cirrhy neither collects data for tracking nor shares data with
  data brokers.
- **No third-party SDK that collects anything.** The app's dependencies are the
  Flutter framework, the platform preference/file-picker/paths plugins, and a
  hashing library.

## Permissions Cirrhy asks for

- **Access to the folder you choose.** You grant it by picking the folder; the
  app stores a security-scoped bookmark on Apple platforms and a persisted
  Storage Access Framework permission on Android. It is used only to read and
  write `cirrhy.json`, its temporary write file, and backup copies. Cirrhy does
  not read, index, or transmit any other file in that folder.
- **Notifications**, on Android 13+ and on iOS. Used for exactly one thing: the
  badge that shows a timer is running on that device. Declining costs you the
  badge and nothing else. No notification content leaves the device.

## The sync service you choose

Cirrhy is designed to be synced by putting its folder inside a service you
already use — Dropbox, iCloud Drive, Nextcloud, Syncthing, or anything else.
That is your arrangement with that provider, under their terms and their privacy
policy. Cirrhy contains no integration with any of them, sends them nothing
directly, and has no visibility into what they do with the folder. If this
matters to you, choose accordingly — including choosing a purely local folder,
which works fine for a single device.

## Children

Cirrhy is a general-purpose tool that is not directed at children. It collects
no data from anyone, of any age.

## Deleting your data

There is nothing held anywhere for you to request the deletion of. Your data is
your file: delete `cirrhy.json` and the app's backups (uninstalling the app
removes the backups) and it is gone. No account to close, no request to file, no
retention period on our side, because there is no our side.

## Who publishes Cirrhy

Cirrhy is free and open-source software, Apache 2.0, copyright 2026 Lóránd
Somogyi. The complete source — including every line that touches your data — is
at <https://github.com/lorands/cirrhy> and can be audited by anyone.

The App Store listing is published by **Appific Kft.** (Appific Korlátolt
Felelősségű Társaság), under a distribution arrangement with the author.
Appific receives no user data from the app, for the same reason nobody else
does: the app transmits none.

## Changes to this policy

This document is versioned in the public repository, so every change to it is
visible with its date and reasoning in the commit history. Material changes will
be noted in the release notes of the version that introduces them.

## Contact

- Bugs, questions, and anything else public: <https://github.com/lorands/cirrhy/issues>
- Privacy questions specifically: **<lorand.somogyi@appific.app>**
