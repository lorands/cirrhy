# Cirrhy Support

Cirrhy is free and open-source, maintained by one person. Support is genuine but
best-effort — there is no support contract behind it, and this page says plainly
what that means.

## Reporting a bug or asking a question

**<https://github.com/lorands/cirrhy/issues>** — public, searchable, and the only
channel that reliably gets looked at. Search first; someone may have hit it
already.

What makes a report actionable:

- **Platform and OS version** — iPhone 15 / iOS 18.2, Manjaro / Wayland, etc.
- **The app version**, from Settings → About.
- **What you did, what happened, what you expected.** In that order.
- **Whether the folder is synced**, and by what. A large share of anything
  strange involves the sync client's behaviour, so this narrows it fast.
- **Whether more than one device is pointed at the same document.**

You can write in English or Hungarian.

## If your data looks wrong

Cirrhy takes a backup into app-private storage before writes it cannot make
atomically, and whenever you press **Back up now** in Settings → Data folder. If
records have gone missing or an edit went badly:

1. **Do not copy a backup over `cirrhy.json`.** This is the one recovery move
   that looks right and is wrong. Cirrhy merges at the record level, so an
   offline device's newer deletions will merge back in days later and silently
   re-kill exactly the records you restored, long after anyone remembers why.
2. **Stop the timer** on the affected device so nothing new is being written.
3. **Take a copy of the current file** somewhere outside the synced folder,
   before doing anything else.
4. **Recover at the record level.** A backup is a *source document*, not a
   rollback button: the records you want back are written into the live document
   with fresh modification times, so they out-date whatever killed them and
   every device converges through ordinary merge. The format is specified for
   exactly this — see
   [`packages/cirrhy_merge/doc/llms.md`](../../packages/cirrhy_merge/doc/llms.md)
   — and in practice this is a job for an AI agent with your file and the
   backup. The reasoning is in [DESIGN.md](../../DESIGN.md) §11.

Open an issue if you want a hand with it.

## Things that are not bugs

- **Two devices both showing a running timer.** Deliberate. The running timer is
  per-device, and Cirrhy surfaces the other device's timer for you to reconcile
  rather than silently discarding one of them.
- **The app refusing to start until you pick a folder.** Also deliberate. There
  is no default location, because every candidate default is either not synced
  or not stable across a reinstall. Pick any folder; a local one is fine.
- **Your edits not appearing on another device.** Cirrhy writes to a file; the
  file gets to your other device by whatever you chose to sync it with. If the
  sync client has not delivered it yet, Cirrhy has nothing to read. The sync
  status line, and pull-to-refresh on the Timer screen, show and force a re-read.
- **The translations reading oddly.** Known: the shipped translations have not
  been reviewed by native speakers yet. Corrections are very welcome, and are
  one file.

## Known limitations

- **Windows is built by CI but has not been tested by anyone.** Reports welcome,
  and labelled as such on the Releases page.
- **No importers ship with the app.** Migrating from another tracker goes
  through the file format instead — see the README's *Importing from another
  tracker*.
- **No report builder beyond the Reports screen.** Arbitrary pivots, charts and
  spreadsheets go through the format too, with a packaged agent skill for it.

## Security issues

If you believe you have found something with security or data-loss impact,
please open an issue marked as such, or reach the maintainer privately at
**<lorand.somogyi@appific.app>** rather than posting details publicly first.
