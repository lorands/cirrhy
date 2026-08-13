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

import '../l10n/generated/app_localizations.dart';
import '../storage/document_directory.dart';
import '../storage/document_location.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'document_location_preference.dart';
import 'locale_preference.dart';

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
    this.firstRun = false,
    this.onContinue,
  });

  final LocalePreference localePreference;
  final DocumentLocationPreference locationPreference;
  final DocumentDirectory directory;

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

class _SettingsScreenState extends State<SettingsScreen> {
  _Note _note = _Note.none;
  bool _picking = false;

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final body = ListView(
      padding: const EdgeInsets.all(Space.x6),
      children: [
        if (widget.firstRun) ...[
          const _FirstRunHeader(),
          const SizedBox(height: Space.x8),
        ],
        _StorageSection(
          location: widget.locationPreference.location,
          note: _note,
          busy: _picking,
          onPick: _picking ? null : _pick,
        ),
        const SizedBox(height: Space.x8),
        _LanguageSection(preference: widget.localePreference),
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
  });

  final DocumentLocation? location;
  final _Note note;
  final bool busy;
  final VoidCallback? onPick;

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
