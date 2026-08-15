// Copyright 2026 Lóránd Somogyi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:flutter/material.dart';

import '../about/version.dart';
import '../data/document_session.dart';
import '../l10n/generated/app_localizations.dart';
import '../storage/document_directory.dart';
import '../storage/document_location.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'about_screen.dart';
import 'document_location_preference.dart';
import 'locale_preference.dart';
import 'theme_preference.dart';

/// The preferences screen, and the first screen the app ever shows.
///
/// DESIGN.md §4.6: first run is this same screen in a first-run presentation
/// rather than a separate wizard. Both ask the same question with the same
/// controls, so there is one place a setting can be changed, one set of
/// strings, and no second copy of the picker to drift out of step.
///
/// It holds the two settings that are device-scoped by nature — where the file
/// lives and which language the UI speaks. Neither is in the Cirrhy document
/// (§3.7): the same person's phone and work laptop legitimately differ on
/// both, and an iOS bookmark would be meaningless on Linux anyway.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.localePreference,
    required this.locationPreference,
    required this.directory,
    this.themePreference,
    this.session,
    this.firstRun = false,
    this.onContinue,
  });

  final LocalePreference localePreference;
  final DocumentLocationPreference locationPreference;
  final DocumentDirectory directory;

  /// The open session, which is what the manual backup (DESIGN.md §11) runs
  /// through — the copy has to queue behind every pending save. Null on first
  /// run, where no document exists to copy yet, and in tests that do not
  /// exercise the backup row; the row simply stays away.
  final DocumentSession? session;

  /// Null in tests that do not exercise theming, and during first run, where
  /// the reduced content never shows the Appearance row anyway. When present,
  /// the General section grows a row for it.
  final ThemePreference? themePreference;

  /// Drops the app bar, leads with the welcome, and offers the way forward
  /// only once a folder has been chosen.
  final bool firstRun;

  /// What the first-run button does. Falls back to popping the route.
  ///
  /// First run does not advance on its own the moment a folder is picked,
  /// which it easily could: the confirmation saying whether the file is about
  /// to be created or merged into would flash past unread, and that sentence
  /// is the whole reason the adopt case is safe to offer without a prompt.
  final VoidCallback? onContinue;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// What to say under the folder, if anything.
enum _Note { none, willCreate, willAdopt, unavailable, pickFailed }

/// What to say under the backup button, if anything.
enum _BackupNote { none, saved, nothingYet, failed }

class _SettingsScreenState extends State<SettingsScreen> {
  _Note _note = _Note.none;
  bool _picking = false;
  _BackupNote _backupNote = _BackupNote.none;
  String? _backupName;
  bool _backingUp = false;

  @override
  void initState() {
    super.initState();
    // A handle can stop resolving between runs (§4.4), and this screen is
    // where the user fixes that, so it is also where the app checks.
    if (widget.locationPreference.isChosen) _checkStillReachable();
  }

  Future<void> _checkStillReachable() async {
    final location = widget.locationPreference.location;
    if (location == null) return;
    final available = await widget.directory.isAvailable(location);
    if (!mounted || available) return;
    setState(() => _note = _Note.unavailable);
  }

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final picked = await widget.directory.pick();
      if (picked == null) return; // Cancelled; leave everything as it was.

      // Look before committing, so the confirmation can say which of the two
      // things is about to happen. The adopt case is not an edge case — it is
      // what every device after the first sees.
      final existing = await widget.directory.existingDocuments(picked);
      await widget.locationPreference.set(picked);
      if (!mounted) return;
      setState(
        () => _note = existing.isEmpty ? _Note.willCreate : _Note.willAdopt,
      );
    } on Object {
      // Includes DocumentLocationUnavailable: a folder that cannot be listed
      // the moment after it was picked is one the user should pick again.
      if (mounted) setState(() => _note = _Note.pickFailed);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _backUp() async {
    final session = widget.session;
    if (session == null) return;
    setState(() {
      _backingUp = true;
      _backupNote = _BackupNote.none;
    });
    try {
      final name = await session.backUpNow();
      if (!mounted) return;
      setState(() {
        _backupName = name;
        _backupNote = name == null ? _BackupNote.nothingYet : _BackupNote.saved;
      });
    } on Object {
      // Includes DocumentLocationUnavailable. A backup that cannot be written
      // costs nothing but this note — the document itself is untouched.
      if (mounted) setState(() => _backupNote = _BackupNote.failed);
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final storage = _StorageSection(
      location: widget.locationPreference.location,
      note: _note,
      busy: _picking,
      onPick: _picking ? null : _pick,
      // No backup row before a folder is chosen: there is no file to copy
      // and no folder to copy it into. First run never passes a session.
      onBackUp: widget.session == null || !widget.locationPreference.isChosen
          ? null
          : _backUp,
      backingUp: _backingUp,
      backupNote: _backupNote,
      backupName: _backupName,
    );

    // First run's content is deliberately reduced — no Appearance, no About,
    // no footnote — and must stay exactly what it always was. This branch is
    // kept separate from the full layout below rather than folded into it
    // with a bunch of `if (!firstRun)` guards threaded through one shared
    // section, because that would make an unrelated edit to the About
    // section a place a first-run regression could hide.
    final body = ListView(
      padding: const EdgeInsets.all(Space.x6),
      children: widget.firstRun
          ? [
              const _FirstRunHeader(),
              const SizedBox(height: Space.x8),
              storage,
              const SizedBox(height: Space.x8),
              _LanguageSection(preference: widget.localePreference),
            ]
          : [
              _GeneralSection(
                localePreference: widget.localePreference,
                themePreference: widget.themePreference,
              ),
              const SizedBox(height: Space.x8),
              storage,
              const SizedBox(height: Space.x8),
              const _AboutSection(),
              const SizedBox(height: Space.x8),
              _DeviceScopedFootnote(text: l10n.deviceScopedNote),
            ],
    );

    return Scaffold(
      appBar: widget.firstRun ? null : AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Settings read badly as full-width text on a desktop window.
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Expanded(child: body),
                // Pinned rather than the last item in the list. It is the only
                // way out of this screen, and a primary action that scrolls
                // off a short phone screen reads as no way out at all.
                if (widget.firstRun)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.x6,
                      0,
                      Space.x6,
                      Space.x6,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        // Disabled until there is somewhere to keep the data.
                        // The file is the app's entire state, so there is
                        // nothing to show before it exists.
                        onPressed: widget.locationPreference.isChosen
                            ? (widget.onContinue ??
                                  () => Navigator.of(context).maybePop())
                            : null,
                        child: Text(l10n.firstRunContinue),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FirstRunHeader extends StatelessWidget {
  const _FirstRunHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = CirrhyTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.firstRunTitle, style: text.headlineMedium),
        const SizedBox(height: Space.x3),
        Text(
          l10n.firstRunBody,
          style: text.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _StorageSection extends StatelessWidget {
  const _StorageSection({
    required this.location,
    required this.note,
    required this.busy,
    required this.onPick,
    required this.onBackUp,
    required this.backingUp,
    required this.backupNote,
    required this.backupName,
  });

  final DocumentLocation? location;
  final _Note note;
  final bool busy;
  final VoidCallback? onPick;

  /// Null hides the backup row entirely — first run, or no session to queue
  /// the copy behind.
  final VoidCallback? onBackUp;
  final bool backingUp;
  final _BackupNote backupNote;
  final String? backupName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = CirrhyTheme.of(context);
    final chosen = location != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.storageSectionLabel, style: text.labelLarge),
        const SizedBox(height: Space.x1),
        Text(
          l10n.storageDescription,
          style: text.labelSmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.x4),
        Container(
          padding: const EdgeInsets.all(Space.x4),
          decoration: BoxDecoration(
            color: colors.subtle,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  // The label, never the handle: on Android that is a content
                  // URI and on Apple platforms a bookmark blob.
                  chosen ? location!.label : l10n.storageNotChosen,
                  style: chosen
                      ? text.bodyMedium
                      : text.bodyMedium?.copyWith(color: colors.textMuted),
                ),
              ),
              const SizedBox(width: Space.x3),
              if (busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                OutlinedButton(
                  onPressed: onPick,
                  child: Text(chosen ? l10n.storageChange : l10n.storageChoose),
                ),
            ],
          ),
        ),
        if (note != _Note.none) ...[
          const SizedBox(height: Space.x3),
          _NoteLine(note: note),
        ],
        if (onBackUp != null) ...[
          const SizedBox(height: Space.x4),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.backupDescription,
                  style: text.labelSmall?.copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: Space.x3),
              if (backingUp)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                OutlinedButton(
                  onPressed: onBackUp,
                  child: Text(l10n.backupNow),
                ),
            ],
          ),
          if (backupNote != _BackupNote.none) ...[
            const SizedBox(height: Space.x3),
            _BackupNoteLine(note: backupNote, name: backupName),
          ],
        ],
      ],
    );
  }
}

/// The line under the backup button, in the shape of [_NoteLine] above it.
class _BackupNoteLine extends StatelessWidget {
  const _BackupNoteLine({required this.note, required this.name});

  final _BackupNote note;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    final (String message, Color tone, IconData icon) = switch (note) {
      // The file name is the message: it is what the user will look for in
      // their folder, and what they would quote when restoring from it.
      _BackupNote.saved => (
        l10n.backupSavedAs(name ?? ''),
        colors.info,
        Icons.check,
      ),
      _BackupNote.nothingYet => (
        l10n.backupNothingYet,
        colors.warning,
        Icons.info_outline,
      ),
      _BackupNote.failed => (
        l10n.backupFailed,
        colors.danger,
        Icons.error_outline,
      ),
      _BackupNote.none => ('', colors.textMuted, Icons.info_outline),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: tone),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Text(message, style: text.labelSmall?.copyWith(color: tone)),
        ),
      ],
    );
  }
}

class _NoteLine extends StatelessWidget {
  const _NoteLine({required this.note});

  final _Note note;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    final (String message, Color tone, IconData icon) = switch (note) {
      _Note.willCreate => (l10n.storageWillCreate, colors.info, Icons.add),
      // Merged, never replaced. Saying this out loud is the point: the user
      // is about to point a second device at a folder that already holds
      // their history, and "will be merged" is the promise §3.2 keeps.
      _Note.willAdopt => (l10n.storageWillAdopt, colors.info, Icons.merge),
      _Note.unavailable => (
        l10n.storageUnavailable,
        colors.warning,
        Icons.warning_amber,
      ),
      _Note.pickFailed => (
        l10n.storagePickFailed,
        colors.danger,
        Icons.error_outline,
      ),
      _Note.none => ('', colors.textMuted, Icons.info_outline),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: tone),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Text(message, style: text.labelSmall?.copyWith(color: tone)),
        ),
      ],
    );
  }
}

/// The General section: language, plus appearance once a [ThemePreference]
/// is available to back it.
///
/// This is the one section that gathers rows which already had a home before
/// this section existed — [_LanguageSection] is unchanged from what first run
/// shows, reused here rather than re-implemented, so the two presentations
/// cannot drift apart on what "Language" looks like.
class _GeneralSection extends StatelessWidget {
  const _GeneralSection({required this.localePreference, this.themePreference});

  final LocalePreference localePreference;
  final ThemePreference? themePreference;

  @override
  Widget build(BuildContext context) {
    final theme = themePreference;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).generalSectionLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: Space.x4),
        _LanguageSection(preference: localePreference),
        if (theme != null) ...[
          const SizedBox(height: Space.x4),
          _AppearanceSection(preference: theme),
        ],
      ],
    );
  }
}

class _LanguageSection extends StatelessWidget {
  const _LanguageSection({required this.preference});

  final LocalePreference preference;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).languageLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: Space.x3),
        LanguagePicker(preference: preference),
      ],
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.preference});

  final ThemePreference preference;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).appearanceLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: Space.x3),
        AppearancePicker(preference: preference),
      ],
    );
  }
}

/// The language override.
///
/// Each language is listed in its own name — a picker that says "Hungarian" is
/// no use to someone who cannot read the language currently on screen, which
/// is exactly the person using it. That is what the `languageName` key is for.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, required this.preference});

  final LocalePreference preference;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);

    return DropdownMenu<Locale?>(
      initialSelection: preference.locale,
      // Not languageSystem: that is one of the values, and a label repeating
      // the selected value tells the reader nothing.
      label: Text(l10n.languageLabel),
      onSelected: preference.set,
      textStyle: Theme.of(context).textTheme.bodyMedium,
      dropdownMenuEntries: [
        DropdownMenuEntry(value: null, label: l10n.languageSystem),
        for (final locale in AppLocalizations.supportedLocales)
          DropdownMenuEntry(
            value: locale,
            label: lookupAppLocalizations(locale).languageName,
            leadingIcon: preference.locale?.languageCode == locale.languageCode
                ? Icon(Icons.check, size: 18, color: colors.brand)
                : const SizedBox(width: 18),
          ),
      ],
    );
  }
}

/// The light/dark override, the same row shape as [LanguagePicker] right
/// above it.
class AppearancePicker extends StatelessWidget {
  const AppearancePicker({super.key, required this.preference});

  final ThemePreference preference;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);

    Icon? check(ThemeMode mode) => preference.mode == mode
        ? Icon(Icons.check, size: 18, color: colors.brand)
        : null;

    return DropdownMenu<ThemeMode>(
      initialSelection: preference.mode,
      label: Text(l10n.appearanceLabel),
      onSelected: (mode) {
        if (mode != null) preference.set(mode);
      },
      textStyle: Theme.of(context).textTheme.bodyMedium,
      dropdownMenuEntries: [
        DropdownMenuEntry(
          value: ThemeMode.system,
          label: l10n.themeSystem,
          leadingIcon: check(ThemeMode.system) ?? const SizedBox(width: 18),
        ),
        DropdownMenuEntry(
          value: ThemeMode.light,
          label: l10n.themeLight,
          leadingIcon: check(ThemeMode.light) ?? const SizedBox(width: 18),
        ),
        DropdownMenuEntry(
          value: ThemeMode.dark,
          label: l10n.themeDark,
          leadingIcon: check(ThemeMode.dark) ?? const SizedBox(width: 18),
        ),
      ],
    );
  }
}

/// The About section: a link to the full [AboutScreen] and a shortcut
/// straight to the licence page, matching Penpot screen E1.
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = CirrhyTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.aboutSectionLabel, style: text.labelLarge),
        const SizedBox(height: Space.x3),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              _AboutRow(
                label: l10n.aboutCirrhy,
                trailing: 'v$appVersion',
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
              ),
              Divider(height: 1, color: colors.border),
              _AboutRow(
                label: l10n.licenseLabel,
                trailing: 'Apache 2.0',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Cirrhy',
                  applicationVersion: appVersion,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.label,
    required this.trailing,
    required this.onTap,
  });

  final String label;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = CirrhyTheme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x4,
          vertical: Space.x3,
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: text.bodyMedium)),
            Text(
              trailing,
              style: text.labelSmall?.copyWith(color: colors.textMuted),
            ),
            const SizedBox(width: Space.x2),
            Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// The reminder that closes the screen: DESIGN.md §3.7 stated in the user's
/// own words, so the device-scoped choices right above it do not read as an
/// unexplained oddity.
class _DeviceScopedFootnote extends StatelessWidget {
  const _DeviceScopedFootnote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: colors.textMuted),
    );
  }
}
