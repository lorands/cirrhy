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
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/entity_chip.dart';
import 'task_picker_sheet.dart';

/// Opens the start-timer sheet (Penpot "09 · Screens & Flow", B3): a
/// description, an optional task (via the picker, B4) and up to four
/// one-tap-restart chips built from recently logged work.
Future<void> showStartTimerSheet(
  BuildContext context,
  DocumentSession session,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _StartTimerSheet(session: session, editing: false),
  );
}

/// Opens the same sheet in edit mode, for the running timer's card — there is
/// no Penpot mockup for this, so it follows the app's own conventions rather
/// than inventing new ones: same sheet, same picker, but prefilled from
/// [DocumentSession.myTimer] and saving through [DocumentSession.updateTimer]
/// instead of starting a new timer, so `startedAt` (and the elapsed time
/// already on the clock) never moves.
Future<void> showEditTimerSheet(BuildContext context, DocumentSession session) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _StartTimerSheet(session: session, editing: true),
  );
}

class _StartTimerSheet extends StatefulWidget {
  const _StartTimerSheet({required this.session, required this.editing});

  final DocumentSession session;

  /// Start mode creates a new timer; edit mode rewrites the running one in
  /// place. The two share every widget below except the title, the primary
  /// button and the "Recent" section — restarting from a recent entry while
  /// editing the timer you are already in would be a confusing second way to
  /// do the same thing.
  final bool editing;

  @override
  State<_StartTimerSheet> createState() => _StartTimerSheetState();
}

class _StartTimerSheetState extends State<_StartTimerSheet> {
  late final TextEditingController _description;
  TaskChoice? _choice;

  @override
  void initState() {
    super.initState();
    // Prefilled from whatever this device's timer holds right now — read
    // once, at open, exactly like every other sheet's initial state. A
    // concurrent edit arriving mid-sheet is not reflected, same as the
    // start-timer sheet not reacting to entries logged while it is open.
    final timer = widget.editing ? widget.session.myTimer : null;
    _description = TextEditingController(text: timer?.description ?? '');
    if (timer != null && (timer.taskId != null || timer.projectId != null)) {
      _choice = TaskChoice(taskId: timer.taskId, projectId: timer.projectId);
    }
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickTask() async {
    final choice = await showTaskPicker(context, widget.session);
    if (choice != null && mounted) setState(() => _choice = choice);
  }

  /// Starts a new timer, or saves the running one in place — the race where
  /// it stopped (locally, or via another device's merge) while this sheet was
  /// open needs no special handling here: [DocumentSession.updateTimer] is
  /// already a no-op with nothing running, so this just closes.
  Future<void> _submit({
    String? projectId,
    String? taskId,
    String? description,
  }) async {
    final navigator = Navigator.of(context);
    final resolvedProjectId = projectId ?? _choice?.projectId;
    final resolvedTaskId = taskId ?? _choice?.taskId;
    final resolvedDescription = description ?? _description.text.trim();
    if (widget.editing) {
      await widget.session.updateTimer(
        projectId: resolvedProjectId,
        taskId: resolvedTaskId,
        description: resolvedDescription,
      );
    } else {
      await widget.session.startTimer(
        projectId: resolvedProjectId,
        taskId: resolvedTaskId,
        description: resolvedDescription,
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final session = widget.session;
    // Restart-from-recent has no place while editing the timer already
    // running — hence not even computed in that mode.
    final recents = widget.editing
        ? const <_RecentChoice>[]
        : _recentChoices(session, colors);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.xl),
          ),
        ),
        child: SafeArea(
          top: false,
          // The keyboard can shrink the sheet below its content's height on
          // a short phone; scrolling absorbs the difference instead of
          // overflowing.
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x6,
                Space.x3,
                Space.x6,
                Space.x6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.border,
                        borderRadius: BorderRadius.circular(Radii.full),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.x4),
                  Text(
                    widget.editing ? l10n.editTimerTitle : l10n.startTimerTitle,
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: Space.x4),
                  TextField(
                    key: const Key('startTimerSheetDescription'),
                    controller: _description,
                    autofocus: true,
                    decoration: InputDecoration(hintText: l10n.timerIdleHint),
                  ),
                  const SizedBox(height: Space.x3),
                  _TaskSelectorRow(
                    choice: _choice,
                    session: session,
                    onTap: _pickTask,
                  ),
                  if (recents.isNotEmpty) ...[
                    const SizedBox(height: Space.x5),
                    Text(
                      l10n.recentLabel,
                      style: text.labelSmall?.copyWith(color: colors.textMuted),
                    ),
                    const SizedBox(height: Space.x2),
                    Wrap(
                      spacing: Space.x2,
                      runSpacing: Space.x2,
                      children: [
                        for (final r in recents)
                          InkWell(
                            borderRadius: BorderRadius.circular(Radii.full),
                            onTap: () => _submit(
                              projectId: r.projectId,
                              taskId: r.taskId,
                              description: r.description,
                            ),
                            child: EntityChip(
                              label: r.label,
                              dotColor: r.color,
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: Space.x6),
                  SizedBox(
                    width: double.infinity,
                    // Edit mode reuses entry_edit_screen's plain Save button —
                    // no play icon, since nothing is being (re)started — while
                    // start mode keeps its own icon button.
                    child: widget.editing
                        ? FilledButton(
                            // A plain text lookup would also match the idle
                            // card's own Start button, still mounted
                            // underneath this sheet.
                            key: const Key('startTimerSheetStart'),
                            onPressed: () => _submit(),
                            child: Text(l10n.saveAction),
                          )
                        : FilledButton.icon(
                            key: const Key('startTimerSheetStart'),
                            onPressed: () => _submit(),
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: Text(l10n.timerStart),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskSelectorRow extends StatelessWidget {
  const _TaskSelectorRow({
    required this.choice,
    required this.session,
    required this.onTap,
  });

  final TaskChoice? choice;
  final DocumentSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    final chosen = choice;
    // A choice can be a bare project — taskId null, projectId set — so the
    // project must be looked up from the choice itself, not only derived
    // from a task that may not exist.
    final task = chosen?.taskId == null
        ? null
        : session.taskById(chosen!.taskId);
    final project = session.projectById(task?.projectId ?? chosen?.projectId);
    final client = session.clientById(project?.clientId);

    Widget content;
    if (chosen == null || (task == null && project == null)) {
      content = Text(
        l10n.timerSelectTask,
        style: text.bodyLarge?.copyWith(color: colors.textMuted),
      );
    } else {
      final label = [
        if (client != null) client.name,
        if (project != null) project.name,
        if (task != null) task.name,
      ].join(' › ');
      content = EntityChip(
        label: label,
        dotColor: parseProjectColor(project?.color) ?? colors.brand,
      );
    }

    return InkWell(
      // Same reason as the Start button's key: the idle card underneath
      // shows the identical "Select task" text for its own inert chip.
      key: const Key('startTimerSheetTaskSelector'),
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x4,
          vertical: Space.x3,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: colors.borderControl),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          children: [
            Expanded(child: content),
            Icon(Icons.expand_more, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _RecentChoice {
  const _RecentChoice({
    required this.projectId,
    required this.taskId,
    required this.description,
    required this.label,
    required this.color,
  });

  final String? projectId;
  final String? taskId;
  final String description;
  final String label;
  final Color color;
}

/// Up to four one-tap-restart chips, built from the most recently logged
/// entries: newest first, unique by the (project, task, description) triple
/// that [DocumentSession.startTimer] actually carries, and skipping entries
/// that carry none of the three — nothing a chip could usefully show.
List<_RecentChoice> _recentChoices(
  DocumentSession session,
  CirrhyColors colors,
) {
  final seen = <String>{};
  final result = <_RecentChoice>[];
  for (final entry in session.document.entriesByRecency()) {
    final label = entry.description.isNotEmpty
        ? entry.description
        : session.taskById(entry.taskId)?.name ??
              session.projectById(entry.projectId)?.name ??
              '';
    if (label.isEmpty) continue;
    final key = '${entry.projectId}|${entry.taskId}|${entry.description}';
    if (!seen.add(key)) continue;
    final project = session.projectById(entry.projectId);
    result.add(
      _RecentChoice(
        projectId: entry.projectId,
        taskId: entry.taskId,
        description: entry.description,
        label: label,
        color: parseProjectColor(project?.color) ?? colors.brand,
      ),
    );
    if (result.length == 4) break;
  }
  return result;
}
