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
import '../l10n/generated/app_localizations.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/entity_chip.dart';

/// What the task picker (B4) hands back to whatever opened it: a task, with
/// the project it implies. The picker only ever returns tasks — never a bare
/// project — so [projectId] simply mirrors the chosen task's own project,
/// which may itself be null (the "no project" bucket).
class TaskChoice {
  const TaskChoice({required this.taskId, this.projectId});

  final String taskId;
  final String? projectId;
}

/// Opens the task picker (Penpot "09 · Screens & Flow", B4): search, a
/// "Recent" shortlist of recently-used tasks, and the full client → project →
/// task hierarchy, plus a way to create a task on the spot. Returns the
/// chosen task, or null if the sheet was dismissed without choosing one.
Future<TaskChoice?> showTaskPicker(
  BuildContext context,
  DocumentSession session,
) {
  return showModalBottomSheet<TaskChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TaskPickerSheet(session: session),
  );
}

class _TaskPickerSheet extends StatefulWidget {
  const _TaskPickerSheet({required this.session});

  final DocumentSession session;

  @override
  State<_TaskPickerSheet> createState() => _TaskPickerSheetState();
}

class _TaskPickerSheetState extends State<_TaskPickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _query = _search.text));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _choose(String taskId, String? projectId) => Navigator.of(
    context,
  ).pop(TaskChoice(taskId: taskId, projectId: projectId));

  Future<void> _createTask(String name) async {
    final now = DateTime.now().toUtc();
    final task = Task(
      id: uuidV4(),
      modified: now,
      name: name,
      projectId: null,
      locationChanged: now,
    );
    await widget.session.put(task);
    if (mounted) _choose(task.id, null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final document = widget.session.document;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(Radii.xl),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: Space.x3),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(Radii.full),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.x6,
                    Space.x4,
                    Space.x6,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.chooseTaskTitle,
                      style: text.headlineSmall,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.x6,
                    Space.x4,
                    Space.x6,
                    0,
                  ),
                  child: TextField(
                    key: const Key('taskPickerSearch'),
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: l10n.searchTasksHint,
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.x6,
                      Space.x4,
                      Space.x6,
                      Space.x4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _RecentTasksSection(
                          session: widget.session,
                          query: _query,
                          onChoose: _choose,
                        ),
                        _AllSection(
                          document: document,
                          query: _query,
                          onChoose: _choose,
                        ),
                        const SizedBox(height: Space.x4),
                        Divider(color: colors.border, height: 1),
                        const SizedBox(height: Space.x3),
                        _NewTaskRow(
                          initialText: _search.text,
                          onCreate: _createTask,
                        ),
                      ],
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

class _RecentTasksSection extends StatelessWidget {
  const _RecentTasksSection({
    required this.session,
    required this.query,
    required this.onChoose,
  });

  final DocumentSession session;
  final String query;
  final void Function(String taskId, String? projectId) onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final q = query.trim().toLowerCase();

    final rows = <Widget>[];
    for (final task in _recentTasks(session)) {
      final project = session.projectById(task.projectId);
      final client = session.clientById(project?.clientId);
      if (q.isNotEmpty &&
          !_matches(q, client?.name, project?.name, task.name)) {
        continue;
      }
      rows.add(
        _TaskListRow(
          task: task,
          project: project,
          client: client,
          showDot: true,
          showCaption: true,
          showChevron: false,
          onTap: () => onChoose(task.id, task.projectId),
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.recentLabel,
          style: text.labelSmall?.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: Space.x1),
        ...rows,
        const SizedBox(height: Space.x4),
      ],
    );
  }
}

class _AllSection extends StatelessWidget {
  const _AllSection({
    required this.document,
    required this.query,
    required this.onChoose,
  });

  final CirrhyDocument document;
  final String query;
  final void Function(String taskId, String? projectId) onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final q = query.trim().toLowerCase();

    final clientSections = <Widget>[];

    void addClientGroup(
      String label,
      List<Project> projects, {
      String? extraProjectLabel,
      List<Task>? extraTasks,
    }) {
      final projectWidgets = <Widget>[];

      for (final project in projects) {
        final tasks = _tasksOf(document, project.id)
            .where((t) => q.isEmpty || _matches(q, label, project.name, t.name))
            .toList();
        if (q.isNotEmpty && tasks.isEmpty) continue;
        projectWidgets.add(
          _ProjectHeader(
            name: project.name,
            color: parseProjectColor(project.color) ?? colors.brand,
          ),
        );
        for (final task in tasks) {
          projectWidgets.add(
            _TaskListRow(
              task: task,
              showDot: false,
              indent: Space.x8,
              onTap: () => onChoose(task.id, project.id),
            ),
          );
        }
      }

      if (extraTasks != null && extraTasks.isNotEmpty) {
        final tasks = extraTasks
            .where(
              (t) => q.isEmpty || _matches(q, label, extraProjectLabel, t.name),
            )
            .toList();
        if (!(q.isNotEmpty && tasks.isEmpty)) {
          projectWidgets.add(
            _ProjectHeader(name: extraProjectLabel!, color: colors.textMuted),
          );
          for (final task in tasks) {
            projectWidgets.add(
              _TaskListRow(
                task: task,
                showDot: false,
                indent: Space.x8,
                onTap: () => onChoose(task.id, null),
              ),
            );
          }
        }
      }

      if (projectWidgets.isEmpty) return;
      clientSections.add(
        Padding(
          padding: const EdgeInsets.only(top: Space.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Space.x1),
              ...projectWidgets,
            ],
          ),
        ),
      );
    }

    for (final client in _clients(document)) {
      addClientGroup(client.name, _projectsOf(document, client.id));
    }

    final noClientProjects = _projectsOf(document, null);
    final noProjectTasks = _tasksOf(document, null);
    if (noClientProjects.isNotEmpty || noProjectTasks.isNotEmpty) {
      addClientGroup(
        l10n.noClientLabel,
        noClientProjects,
        extraProjectLabel: l10n.noProjectLabel,
        extraTasks: noProjectTasks,
      );
    }

    // "Nothing here yet" means the document truly has nothing in it — not
    // merely that the current search matched nothing, which is a different,
    // unremarkable state this deliberately leaves blank.
    final documentIsEmpty =
        document.clients.isEmpty &&
        document.projects.isEmpty &&
        document.tasks.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.allTasksLabel,
          style: text.labelSmall?.copyWith(color: colors.textMuted),
        ),
        if (clientSections.isEmpty && documentIsEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.x2),
            child: Text(
              l10n.pickerEmpty,
              style: text.bodyMedium?.copyWith(color: colors.textMuted),
            ),
          )
        else
          ...clientSections,
      ],
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(
        left: Space.x4,
        top: Space.x2,
        bottom: Space.x1,
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Space.x2),
          Text(
            name,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// One task row, shared by the "Recent" shortlist and the "All" hierarchy —
/// they differ only in which of dot / caption / chevron / indent apply.
class _TaskListRow extends StatelessWidget {
  const _TaskListRow({
    required this.task,
    required this.onTap,
    this.project,
    this.client,
    this.showDot = true,
    this.showCaption = false,
    this.showChevron = true,
    this.indent = 0,
  });

  final Task task;
  final VoidCallback onTap;
  final Project? project;
  final Client? client;
  final bool showDot;
  final bool showCaption;
  final bool showChevron;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final captionText = showCaption
        ? [
            if (client != null) client!.name,
            if (project != null) project!.name,
          ].join(' › ')
        : '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: indent, top: Space.x2, bottom: Space.x2),
        child: Row(
          children: [
            if (showDot) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: parseProjectColor(project?.color) ?? colors.brand,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Space.x2),
            ],
            Expanded(
              child: Text(
                task.name,
                style: text.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (captionText.isNotEmpty) ...[
              const SizedBox(width: Space.x2),
              Text(
                captionText,
                style: text.labelSmall?.copyWith(color: colors.textMuted),
              ),
            ],
            if (showChevron) ...[
              const SizedBox(width: Space.x1),
              Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

/// "New task…", which turns into an inline text field on tap.
class _NewTaskRow extends StatefulWidget {
  const _NewTaskRow({required this.initialText, required this.onCreate});

  /// Prefilled into the field the moment it is revealed — usually whatever is
  /// currently in the search box, so a search that came up empty becomes the
  /// new task's name with no retyping.
  final String initialText;
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

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    widget.onCreate(name);
  }

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    if (!_editing) {
      return InkWell(
        onTap: () => setState(() {
          _editing = true;
          _controller.text = widget.initialText;
        }),
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
            // Distinguishes this from the search field above it — after
            // this row is revealed, both are on screen at once, sometimes
            // carrying the same prefilled text.
            key: const Key('taskPickerNewTaskField'),
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

bool _matches(String query, String? a, String? b, String? c) {
  bool hit(String? s) => s != null && s.toLowerCase().contains(query);
  return hit(a) || hit(b) || hit(c);
}

List<Client> _clients(CirrhyDocument doc) =>
    doc.clients.values.where((c) => !c.archived).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

List<Project> _projectsOf(CirrhyDocument doc, String? clientId) =>
    doc.projects.values
        .where((p) => !p.archived && p.clientId == clientId)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

List<Task> _tasksOf(CirrhyDocument doc, String? projectId) =>
    doc.tasks.values
        .where((t) => !t.archived && t.projectId == projectId)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

/// The last few distinct tasks used by recent entries, newest first —
/// deliberately entries, not the task list itself, so this reflects what was
/// actually worked on rather than everything that merely exists.
///
/// Filters on [isEffectivelyArchived] rather than the task's own flag: a task
/// whose project (or that project's client) was archived after the entry was
/// logged must still disappear here, exactly as it already does from the
/// hierarchy below, even though its own `archived` flag was never touched.
List<Task> _recentTasks(DocumentSession session, {int limit = 5}) {
  final doc = session.document;
  final seen = <String>{};
  final result = <Task>[];
  for (final entry in doc.entriesByRecency()) {
    final taskId = entry.taskId;
    if (taskId == null) continue;
    final task = doc.tasks[taskId];
    if (task == null || isEffectivelyArchived(doc, task)) continue;
    if (!seen.add(taskId)) continue;
    result.add(task);
    if (result.length == limit) break;
  }
  return result;
}
