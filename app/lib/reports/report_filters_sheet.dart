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
import 'report_query.dart';

/// The report filters sheet (Penpot "09 · Screens & Flow", D2).
///
/// Returns the query with its filter axes replaced, or null if the sheet was
/// dismissed — so backing out of it changes nothing, and the draft the user
/// was building is simply dropped.
///
/// [from] and [to] are the window the report is currently showing. The sheet
/// needs them only to count what the draft filters would keep, which is what
/// the confirming button says out loud before it is pressed.
Future<ReportQuery?> showReportFiltersSheet(
  BuildContext context, {
  required DocumentSession session,
  required ReportQuery query,
  required DateTime from,
  required DateTime to,
}) {
  return showModalBottomSheet<ReportQuery>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        _ReportFiltersSheet(session: session, query: query, from: from, to: to),
  );
}

class _ReportFiltersSheet extends StatefulWidget {
  const _ReportFiltersSheet({
    required this.session,
    required this.query,
    required this.from,
    required this.to,
  });

  final DocumentSession session;
  final ReportQuery query;
  final DateTime from;
  final DateTime to;

  @override
  State<_ReportFiltersSheet> createState() => _ReportFiltersSheetState();
}

class _ReportFiltersSheetState extends State<_ReportFiltersSheet> {
  late Set<String> _clientIds;
  late Set<String> _projectIds;
  late Set<String> _taskIds;
  late bool _billableOnly;

  @override
  void initState() {
    super.initState();
    _clientIds = {...widget.query.clientIds};
    _projectIds = {...widget.query.projectIds};
    _taskIds = {...widget.query.taskIds};
    _billableOnly = widget.query.billableOnly;
  }

  void _toggle(Set<String> axis, String id) {
    setState(() => axis.contains(id) ? axis.remove(id) : axis.add(id));
  }

  void _clear() {
    setState(() {
      _clientIds = {};
      _projectIds = {};
      _taskIds = {};
      _billableOnly = false;
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      widget.query.copyWith(
        clientIds: _clientIds,
        projectIds: _projectIds,
        taskIds: _taskIds,
        billableOnly: _billableOnly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final doc = widget.session.document;

    // Archived things stay out of the pickers but their logged time stays in
    // the reports — the promise `archiveNote` makes on C2/C3. Filtering *by*
    // one is what a picker offers, so this list follows the picker rule.
    final clients =
        doc.clients.values.where((c) => !isEffectivelyArchived(doc, c)).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final projects =
        doc.projects.values
            .where((p) => !isEffectivelyArchived(doc, p))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final tasks =
        doc.tasks.values.where((t) => !isEffectivelyArchived(doc, t)).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    // The live count on the apply button: exactly the query the sheet is
    // about to hand back, run against the window already on screen.
    final matching = entriesInRange(
      doc,
      from: widget.from,
      to: widget.to,
      clientIds: _clientIds,
      projectIds: _projectIds,
      taskIds: _taskIds,
      billableOnly: _billableOnly,
    ).length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.xl),
        ),
      ),
      child: SafeArea(
        top: false,
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
                Text(l10n.filtersTitle, style: text.headlineSmall),
                if (clients.isNotEmpty)
                  _Section(
                    label: l10n.clientsFilterLabel,
                    children: [
                      for (final client in clients)
                        SelectableChip(
                          key: Key('clientFilter-${client.id}'),
                          label: client.name,
                          // Clients carry no colour of their own — only
                          // projects do — so the dot is the brand rather than
                          // a colour borrowed from whichever project happens
                          // to sort first.
                          dotColor: colors.brand,
                          selected: _clientIds.contains(client.id),
                          onTap: () => _toggle(_clientIds, client.id),
                        ),
                    ],
                  ),
                if (projects.isNotEmpty)
                  _Section(
                    label: l10n.projectsFilterLabel,
                    children: [
                      for (final project in projects)
                        SelectableChip(
                          key: Key('projectFilter-${project.id}'),
                          label: project.name,
                          dotColor:
                              parseProjectColor(project.color) ?? colors.brand,
                          selected: _projectIds.contains(project.id),
                          onTap: () => _toggle(_projectIds, project.id),
                        ),
                    ],
                  ),
                if (tasks.isNotEmpty)
                  _Section(
                    label: l10n.tasksFilterLabel,
                    children: [
                      for (final task in tasks)
                        SelectableChip(
                          key: Key('taskFilter-${task.id}'),
                          label: task.name,
                          dotColor: _taskDotColor(doc, task, colors),
                          selected: _taskIds.contains(task.id),
                          onTap: () => _toggle(_taskIds, task.id),
                        ),
                    ],
                  ),
                const SizedBox(height: Space.x5),
                Divider(height: 1, thickness: 1, color: colors.border),
                const SizedBox(height: Space.x2),
                Row(
                  children: [
                    Expanded(
                      child: Text(l10n.billableOnly, style: text.bodyLarge),
                    ),
                    Switch(
                      key: const Key('billableOnlySwitch'),
                      value: _billableOnly,
                      onChanged: (value) =>
                          setState(() => _billableOnly = value),
                    ),
                  ],
                ),
                const SizedBox(height: Space.x5),
                Row(
                  children: [
                    OutlinedButton(
                      key: const Key('clearFiltersButton'),
                      onPressed: _clear,
                      child: Text(l10n.clearAction),
                    ),
                    const SizedBox(width: Space.x3),
                    Expanded(
                      child: FilledButton(
                        key: const Key('applyFiltersButton'),
                        onPressed: _apply,
                        child: Text(l10n.showEntriesAction(matching)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A task's dot borrows its project's colour: a task has none of its own, and
/// leaving it grey would lose the only cue that says which project it is in.
Color _taskDotColor(CirrhyDocument doc, Task task, CirrhyColors colors) {
  final project = task.projectId == null ? null : doc.projects[task.projectId];
  return parseProjectColor(project?.color) ?? colors.brand;
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Space.x5),
        Text(label, style: text.labelSmall?.copyWith(color: colors.textMuted)),
        const SizedBox(height: Space.x2),
        Wrap(spacing: Space.x2, runSpacing: Space.x2, children: children),
      ],
    );
  }
}
