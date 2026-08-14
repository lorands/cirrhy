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

import '../data/document_session.dart';
import '../l10n/generated/app_localizations.dart';
import '../settings/document_location_preference.dart';
import '../storage/document_directory.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';

/// A3 — "Folder unreachable": the clear re-select prompt §4.4 demands when a
/// handle goes stale, shown by the shell on the transition into
/// [SessionStatus.unavailable].
///
/// Re-selecting is the same flow the preferences screen runs — pick, then
/// write the preference; the session's location listener does the relocating.
/// The dialog never touches the store itself, and it dismisses itself the
/// moment the session reports anything other than unavailable, however that
/// recovery happened.
Future<void> showFolderUnreachableDialog(
  BuildContext context, {
  required DocumentSession session,
  required DocumentDirectory directory,
  required DocumentLocationPreference locationPreference,
}) {
  return showDialog<void>(
    context: context,
    // The way out is one of the two buttons; a barrier tap falling through
    // would leave no record of whether the user ever saw the warning.
    barrierDismissible: false,
    builder: (_) => FolderUnreachableDialog(
      session: session,
      directory: directory,
      locationPreference: locationPreference,
    ),
  );
}

class FolderUnreachableDialog extends StatefulWidget {
  const FolderUnreachableDialog({
    super.key,
    required this.session,
    required this.directory,
    required this.locationPreference,
  });

  final DocumentSession session;
  final DocumentDirectory directory;
  final DocumentLocationPreference locationPreference;

  @override
  State<FolderUnreachableDialog> createState() =>
      _FolderUnreachableDialogState();
}

class _FolderUnreachableDialogState extends State<FolderUnreachableDialog> {
  bool _picking = false;
  bool _pickFailed = false;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  /// The dialog exists because the session is unavailable, so it leaves when
  /// that stops being true — whether this dialog's re-select fixed it or a
  /// commit elsewhere found the folder remounted.
  void _onSessionChanged() {
    if (!mounted || _popped) return;
    if (widget.session.status != SessionStatus.unavailable) {
      _popped = true;
      Navigator.of(context).pop();
    }
  }

  Future<void> _reselect() async {
    setState(() {
      _picking = true;
      _pickFailed = false;
    });
    try {
      final picked = await widget.directory.pick();
      if (picked == null) return; // Cancelled; the dialog stays as it was.

      // The preference is the source of truth for where the document lives;
      // the session follows it and relocates (§4.6). Awaiting the queue makes
      // the outcome observable here.
      await widget.locationPreference.set(picked);
      await widget.session.idle;
      if (widget.session.status == SessionStatus.unavailable) {
        // Re-picking the folder the preference already names writes nothing
        // and relocates nothing — the folder may simply be back (a remounted
        // share), so ask through the existing repository before giving up.
        await widget.session.refresh();
      }
      if (!mounted || _popped) return;
      if (widget.session.status == SessionStatus.unavailable) {
        // Picked, but the folder could not be reached either way.
        setState(() => _pickFailed = true);
      }
    } on Object {
      // Includes DocumentLocationUnavailable from the picker itself.
      if (mounted) setState(() => _pickFailed = true);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(Space.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.warningSubtle,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_amber,
                    size: 26,
                    color: colors.warning,
                  ),
                ),
              ),
              const SizedBox(height: Space.x4),
              Text(
                l10n.folderUnreachableTitle,
                style: text.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.x2),
              Text(
                l10n.folderUnreachableBody,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              if (_pickFailed) ...[
                const SizedBox(height: Space.x3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 18, color: colors.danger),
                    const SizedBox(width: Space.x2),
                    Flexible(
                      child: Text(
                        l10n.storagePickFailed,
                        style: text.labelSmall?.copyWith(color: colors.danger),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: Space.x5),
              FilledButton.icon(
                key: const Key('reselectFolderButton'),
                onPressed: _picking ? null : _reselect,
                icon: const Icon(Icons.folder_outlined, size: 18),
                label: Text(l10n.reselectFolderAction),
              ),
              const SizedBox(height: Space.x2),
              TextButton(
                key: const Key('notNowButton'),
                onPressed: () {
                  _popped = true;
                  Navigator.of(context).pop();
                },
                child: Text(l10n.notNowAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
