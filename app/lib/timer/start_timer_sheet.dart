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
    builder: (context) => _StartTimerSheet(session: session),
  );
}

class _StartTimerSheet extends StatefulWidget {
  const _StartTimerSheet({required this.session});

  final DocumentSession session;

  @override
  State<_StartTimerSheet> createState() => _StartTimerSheetState();
}

class _StartTimerSheetState extends State<_StartTimerSheet> {
  final _description = TextEditingController();
  TaskChoice? _choice;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickTask() async {
    final choice = await showTaskPicker(context, widget.session);
    if (choice != null && mounted) setState(() => _choice = choice);
  }

  Future<void> _start({
    String? projectId,
    String? taskId,
    String? description,
  }) async {
    final navigator = Navigator.of(context);
    await widget.session.startTimer(
      projectId: projectId ?? _choice?.projectId,
      taskId: taskId ?? _choice?.taskId,
      description: description ?? _description.text.trim(),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final session = widget.session;
    final recents = _recentChoices(session, colors);

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
                Text(l10n.startTimerTitle, style: text.headlineSmall),
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
                          onTap: () => _start(
                            projectId: r.projectId,
                            taskId: r.taskId,
                            description: r.description,
                          ),
                          child: EntityChip(label: r.label, dotColor: r.color),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.x6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    // A plain text lookup would also match the idle card's
                    // own Start button, still mounted underneath this sheet.
                    key: const Key('startTimerSheetStart'),
                    onPressed: () => _start(),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(l10n.timerStart),
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
