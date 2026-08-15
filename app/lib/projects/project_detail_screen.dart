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

import '../data/document_session.dart';
import '../data/document_views.dart';
import '../l10n/duration_format.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/entity_chip.dart';
import '../widgets/entry_row.dart';
import 'client_picker_sheet.dart';
import 'color_swatch_row.dart';
import 'rename_dialog.dart';

/// Marks a not-provided argument to [_ProjectDetailScreenState._rebuild],
/// distinct from an explicitly-null one — [Project.clientId] must be
/// settable to null (the "no client" case) without that reading as "leave it
/// alone".
const _unset = Object();

/// Project detail (Penpot "09 · Screens & Flow", C3): rename, reassign to a
/// client (a relocation — see [Project.locationChanged]), recolour, manage
/// its tasks, and archive.
class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({
    super.key,
    required this.session,
    required this.projectId,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final DocumentSession session;
  final String projectId;

  /// Where `modified`/`locationChanged` timestamps come from. Overridable
  /// for tests, matching every other screen's clock convention.
  final DateTime Function() clock;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  bool _poppingForMissingProject = false;

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

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  DateTime _now() => widget.clock().toUtc();

  /// Rebuilds [project] field-by-field — the engine's records carry no
  /// `copyWith`. Passing [clientId] is what re-parents the project, and it
  /// alone bumps `locationChanged` (DESIGN.md §3.5): renaming or recolouring
  /// is not a relocation.
  Project _rebuild(
    Project project, {
    String? name,
    Object? clientId = _unset,
    String? color,
    bool? archived,
  }) {
    final now = _now();
    final relocating = !identical(clientId, _unset);
    return Project(
      id: project.id,
      modified: now,
      name: name ?? project.name,
      clientId: relocating ? clientId as String? : project.clientId,
      locationChanged: relocating ? now : project.locationChanged,
      color: color ?? project.color,
      billable: project.billable,
      archived: archived ?? project.archived,
      importSource: project.importSource,
      externalId: project.externalId,
      history: project.history,
    );
  }

  Future<void> _rename(Project project) async {
    final name = await showRenameDialog(context, currentName: project.name);
    if (name == null) return;
    await widget.session.put(_rebuild(project, name: name));
  }

  Future<void> _pickClient(Project project) async {
    final choice = await showClientPicker(context, widget.session);
    if (choice == null) return;
    await widget.session.put(_rebuild(project, clientId: choice.clientId));
  }

  Future<void> _pickColor(Project project, String hex) =>
      widget.session.put(_rebuild(project, color: hex));

  Future<void> _createTask(Project project, String name) async {
    final now = _now();
    await widget.session.put(
      Task(
        id: uuidV4(),
        modified: now,
        name: name,
        projectId: project.id,
        locationChanged: now,
      ),
    );
  }

  Future<void> _archive(Project project) async {
    final navigator = Navigator.of(context);
    await widget.session.put(_rebuild(project, archived: true));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final project = widget.session.document.projects[widget.projectId];

    if (project == null) {
      // Deleted or archived-and-popped out from under us, or a merge from
      // another device removed it. Same pattern as the entry editor: nothing
      // left to show, so pop on the next frame rather than mid-build.
      if (!_poppingForMissingProject) {
        _poppingForMissingProject = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return const Scaffold(body: SizedBox.shrink());
    }

    final client = widget.session.clientById(project.clientId);

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: [
          IconButton(
            key: const Key('projectRenameButton'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _rename(project),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Space.x6),
          children: [
            _ClientLine(project: project, client: client, l10n: l10n),
            const SizedBox(height: Space.x5),
            _MetaCard(
              project: project,
              client: client,
              onPickClient: () => _pickClient(project),
              onPickColor: (hex) => _pickColor(project, hex),
            ),
            const SizedBox(height: Space.x6),
            _SectionLabel(l10n.tasksLabel),
            const SizedBox(height: Space.x2),
            _TasksCard(
              session: widget.session,
              project: project,
              onCreate: (name) => _createTask(project, name),
            ),
            const SizedBox(height: Space.x3),
            Text(
              l10n.taskRunFootnote,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: CirrhyTheme.of(context).textMuted,
              ),
            ),
            const SizedBox(height: Space.x6),
            Center(
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: CirrhyTheme.of(context).danger,
                ),
                onPressed: () => _archive(project),
                child: Text(l10n.archiveProjectAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientLine extends StatelessWidget {
  const _ClientLine({
    required this.project,
    required this.client,
    required this.l10n,
  });

  final Project project;
  final Client? client;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: parseProjectColor(project.color) ?? colors.brand,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: Space.x2),
        Text(
          client?.name ?? l10n.noClientLabel,
          style: text.bodyMedium?.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

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

class _MetaCard extends StatelessWidget {
  const _MetaCard({
    required this.project,
    required this.client,
    required this.onPickClient,
    required this.onPickColor,
  });

  final Project project;
  final Client? client;
  final VoidCallback onPickClient;
  final ValueChanged<String> onPickColor;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: const Key('projectClientRow'),
                onTap: onPickClient,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x2),
                  child: Row(
                    children: [
                      Text(l10n.clientLabel, style: text.bodyMedium),
                      const Spacer(),
                      Text(
                        client?.name ?? l10n.noClientLabel,
                        style: text.bodyMedium?.copyWith(
                          color: client == null ? colors.textMuted : null,
                        ),
                      ),
                      const SizedBox(width: Space.x2),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: colors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.x2),
            Divider(color: colors.border, height: 1),
            const SizedBox(height: Space.x3),
            Text(l10n.colorLabel, style: text.bodyMedium),
            const SizedBox(height: Space.x3),
            ColorSwatchRow(
              selected: project.color ?? projectColorPalette.first,
              onSelect: onPickColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _TasksCard extends StatefulWidget {
  const _TasksCard({
    required this.session,
    required this.project,
    required this.onCreate,
  });

  final DocumentSession session;
  final Project project;
  final Future<void> Function(String name) onCreate;

  @override
  State<_TasksCard> createState() => _TasksCardState();
}

class _TasksCardState extends State<_TasksCard> {
  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final doc = widget.session.document;
    final tasks =
        doc.tasks.values
            .where((t) => t.projectId == widget.project.id && !t.archived)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          for (final task in tasks) ...[
            _TaskRow(session: widget.session, task: task),
            Divider(
              height: 1,
              thickness: 1,
              color: colors.border,
              indent: Space.x4,
              endIndent: Space.x4,
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.x4,
              vertical: Space.x1,
            ),
            child: _NewTaskRow(onCreate: widget.onCreate),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.session, required this.task});

  final DocumentSession session;
  final Task task;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final total = totalFor(session.document, taskId: task.id);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x4,
        vertical: Space.x3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
                const SizedBox(height: Space.x1),
                Text(
                  total == Duration.zero
                      ? l10n.neverStarted
                      : l10n.loggedAmount(
                          formatDuration(total, l10n.localeName),
                        ),
                  style: text.labelSmall?.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.x3),
          RunButton(
            tooltip: l10n.timerRestartTooltip,
            onPressed: () => session.startTimer(
              projectId: task.projectId,
              taskId: task.id,
              description: '',
            ),
          ),
        ],
      ),
    );
  }
}

/// "New task…", which turns into an inline text field on tap — the same
/// shape as the task picker's own new-task row, creating the task straight
/// under this project rather than the picker's unassigned bucket.
class _NewTaskRow extends StatefulWidget {
  const _NewTaskRow({required this.onCreate});

  final Future<void> Function(String name) onCreate;

  @override
  State<_NewTaskRow> createState() => _NewTaskRowState();
}

class _NewTaskRowState extends State<_NewTaskRow> {
  bool _editing = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    await widget.onCreate(name);
    if (mounted) setState(() => _controller.clear());
  }

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    if (!_editing) {
      return InkWell(
        onTap: () => setState(() => _editing = true),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 18, color: colors.brand),
              const SizedBox(width: Space.x2),
              Text(
                l10n.newTaskAction,
                style: text.bodyMedium?.copyWith(
                  color: colors.brand,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('projectNewTaskField'),
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.newTaskHint),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: Space.x2),
        IconButton(
          icon: const Icon(Icons.check),
          onPressed: _submit,
          color: colors.brand,
        ),
      ],
    );
  }
}
