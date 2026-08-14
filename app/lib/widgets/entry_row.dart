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

import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/document_session.dart';
import '../l10n/duration_format.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../timer/entry_edit_screen.dart';
import 'entity_chip.dart';

/// One logged entry, as it appears in every list that shows logged entries:
/// the timer screen's day groups (B2) and the reports entries view (D3).
///
/// Extracted from the timer screen when reports needed the identical row.
/// The two boards draw the same thing down to the 34px run button, and the
/// product constraint behind it is the same in both places — a past entry is
/// one tap from becoming a running timer, from anywhere. Forking the widget
/// would have meant two places to keep that promise.
class EntryRow extends StatelessWidget {
  const EntryRow({
    super.key,
    required this.entry,
    required this.session,
    this.newFromSync = false,
  });

  final TimeEntry entry;

  /// Null renders the row inert: no editor to push, no session to restart
  /// into. Both taps disable together, never one without the other.
  final DocumentSession? session;

  /// F2: this entry arrived in the last refresh's merge rather than being
  /// logged here. Tints the row and adds a caption saying so. Only the timer
  /// list sets it — a report is a different question about the same rows.
  final bool newFromSync;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final currentSession = session;

    final project = currentSession?.projectById(entry.projectId);
    final client = project == null
        ? null
        : currentSession?.clientById(project.clientId);
    final hm = DateFormat.Hm(l10n.localeName);
    final stop = entry.stop;
    // A stop-less entry is the rare case of an open timer that arrived from
    // another device via merge — shown, but with no duration to add up.
    final range = stop == null
        ? '${hm.format(entry.start.toLocal())} – …'
        : '${hm.format(entry.start.toLocal())} – ${hm.format(stop.toLocal())}';
    final hasDescription = entry.description.isNotEmpty;

    return Container(
      // The caption is a third line, so the flagged row is taller — height
      // is otherwise identical to keep the list from shifting elsewhere.
      height: newFromSync ? 80 : 64,
      color: newFromSync ? colors.brandSubtle : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4),
        child: Row(
          children: [
            Expanded(
              // The row body — everything but the run button — opens the
              // entry editor (B5). The run button keeps its own tap target
              // so the two never fight over a single gesture.
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: currentSession == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EntryEditScreen(
                              session: currentSession,
                              entryId: entry.id,
                            ),
                          ),
                        ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasDescription
                                  ? entry.description
                                  : l10n.timerNoDescription,
                              style: hasDescription
                                  ? text.bodyMedium
                                  : text.bodyMedium?.copyWith(
                                      color: colors.textMuted,
                                    ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (project != null) ...[
                              const SizedBox(height: Space.x1),
                              ProjectChip(project: project, client: client),
                            ],
                            if (newFromSync) ...[
                              const SizedBox(height: Space.x1),
                              Text(
                                l10n.newFromSync,
                                style: text.labelSmall?.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.x3),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            range,
                            style: text.labelSmall?.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                          if (stop != null) ...[
                            const SizedBox(height: Space.x1),
                            Text(
                              formatDuration(
                                stop.difference(entry.start),
                                l10n.localeName,
                              ),
                              style: Type.duration.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.x3),
            RunButton(
              tooltip: l10n.timerRestartTooltip,
              onPressed: currentSession == null
                  ? null
                  : () => currentSession.restartFrom(entry),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 36px circular "start a timer from this" button.
///
/// One widget for all three places the design puts it — next to a past entry
/// on the timer screen, next to the same entry in a report, and next to a
/// task on the project detail screen (C3).
class RunButton extends StatelessWidget {
  const RunButton({super.key, required this.tooltip, required this.onPressed});

  final String tooltip;

  /// Null disables the button — restarting needs a session to restart into.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.brandSubtle,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.play_arrow, size: 18, color: colors.brand),
          ),
        ),
      ),
    );
  }
}
