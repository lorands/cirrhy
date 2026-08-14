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
import 'client_detail_screen.dart';
import 'new_project_sheet.dart';
import 'project_detail_screen.dart';

/// The Projects tab (Penpot "09 · Screens & Flow", C1): every client with its
/// non-archived projects, search, and a collapsed Archived section.
///
/// Replaces the `_StubTab` that used to stand in for this destination in
/// `app_shell.dart`. [session] is nullable for the same reason
/// [TimerScreen]'s is: a shell built without the app's real dependencies
/// still needs to render something inert rather than crash.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, this.session, DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  final DocumentSession? session;

  /// Where "this month" is measured from. Overridable for tests, matching
  /// every other screen's clock convention.
  final DateTime Function() clock;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _archivedExpanded = false;

  @override
  void initState() {
    super.initState();
    widget.session?.addListener(_onSessionChanged);
    _search.addListener(() => setState(() => _query = _search.text));
  }

  @override
  void didUpdateWidget(covariant ProjectsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session?.removeListener(_onSessionChanged);
      widget.session?.addListener(_onSessionChanged);
    }
  }

  @override
  void dispose() {
    widget.session?.removeListener(_onSessionChanged);
    _search.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _openNewProject() {
    final session = widget.session;
    if (session == null) return;
    showNewProjectSheet(context, session);
  }

  Future<void> _unarchiveClient(Client client) async {
    final session = widget.session;
    if (session == null) return;
    await session.put(
      Client(
        id: client.id,
        modified: widget.clock().toUtc(),
        name: client.name,
        history: client.history,
      ),
    );
  }

  Future<void> _unarchiveProject(Project project) async {
    final session = widget.session;
    if (session == null) return;
    await session.put(
      Project(
        id: project.id,
        modified: widget.clock().toUtc(),
        name: project.name,
        clientId: project.clientId,
        locationChanged: project.locationChanged,
        color: project.color,
        billable: project.billable,
        history: project.history,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final doc = session?.document ?? const CirrhyDocument.empty();
    final l10n = AppLocalizations.of(context);
    final query = _query.trim().toLowerCase();
    final (from, to) = currentMonthWindow(widget.clock());

    final documentIsEmpty = doc.clients.isEmpty && doc.projects.isEmpty;

    final groups = _buildGroups(doc, query, l10n.noClientLabel);
    final archivedClients = doc.clients.values.where((c) => c.archived).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final archivedProjects =
        doc.projects.values.where((p) => p.archived).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final archivedCount = archivedClients.length + archivedProjects.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.x4,
        Space.x6,
        Space.x4,
        Space.x8,
      ),
      children: [
        _Header(
          title: l10n.tabProjects,
          onAdd: session == null ? null : _openNewProject,
        ),
        const SizedBox(height: Space.x5),
        _SearchField(controller: _search),
        const SizedBox(height: Space.x5),
        if (documentIsEmpty)
          _EmptyState(text: l10n.projectsEmpty)
        else if (groups.isEmpty && query.isNotEmpty)
          const SizedBox.shrink()
        else
          for (final group in groups) ...[
            _ClientCard(
              session: session,
              doc: doc,
              group: group,
              from: from,
              to: to,
            ),
            const SizedBox(height: Space.x4),
          ],
        if (archivedCount > 0)
          _ArchivedCard(
            count: archivedCount,
            expanded: _archivedExpanded,
            onToggle: () =>
                setState(() => _archivedExpanded = !_archivedExpanded),
            clients: archivedClients,
            projects: archivedProjects,
            onUnarchiveClient: _unarchiveClient,
            onUnarchiveProject: _unarchiveProject,
          ),
      ],
    );
  }
}

/// One client (or the "No client" pseudo-group) plus the projects to show
/// under it, already filtered by search.
class _ClientGroup {
  const _ClientGroup({
    required this.client,
    required this.label,
    required this.allProjects,
    required this.visibleProjects,
  });

  /// Null for the "No client" pseudo-group — there is nothing to navigate to.
  final Client? client;
  final String label;

  /// Every non-archived project in the group, independent of the current
  /// search — the header caption and this-month total always reflect the
  /// true total, and (for the "No client" pseudo-group specifically) this is
  /// also what the total is summed over: `totalFor`'s `clientId` filter
  /// can't itself express "no client", since a bare null there means "don't
  /// filter by client at all" rather than "match projects with none".
  final List<Project> allProjects;

  int get projectCount => allProjects.length;

  /// The projects to actually list, narrowed by the search query.
  final List<Project> visibleProjects;
}

List<_ClientGroup> _buildGroups(
  CirrhyDocument doc,
  String query,
  String noClientLabel,
) {
  final groups = <_ClientGroup>[];

  final clients = doc.clients.values.where((c) => !c.archived).toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  void addGroup(Client? client, String label) {
    final allProjects =
        doc.projects.values
            .where((p) => !p.archived && p.clientId == client?.id)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    if (query.isEmpty) {
      if (allProjects.isEmpty && client == null) return;
      groups.add(
        _ClientGroup(
          client: client,
          label: label,
          allProjects: allProjects,
          visibleProjects: allProjects,
        ),
      );
      return;
    }

    final labelMatches = label.toLowerCase().contains(query);
    final visible = labelMatches
        ? allProjects
        : allProjects
              .where((p) => p.name.toLowerCase().contains(query))
              .toList();
    if (!labelMatches && visible.isEmpty) return;
    groups.add(
      _ClientGroup(
        client: client,
        label: label,
        allProjects: allProjects,
        visibleProjects: visible,
      ),
    );
  }

  for (final client in clients) {
    addGroup(client, client.name);
  }
  addGroup(null, noClientLabel);

  return groups;
}

/// The this-month total for [group]'s header caption.
///
/// A real client resolves in one pass via `totalFor`'s own `clientId`
/// filter. The "No client" pseudo-group cannot use that path — passing a
/// bare `null` `clientId` to `totalFor` means "don't filter by client at
/// all", not "match projects with none" — so it sums per project instead,
/// over [_ClientGroup.allProjects] rather than the search-narrowed
/// [_ClientGroup.visibleProjects], so a search never changes the total shown.
Duration _groupTotal(
  CirrhyDocument doc,
  _ClientGroup group,
  DateTime from,
  DateTime to,
) {
  final client = group.client;
  if (client != null) {
    return totalFor(doc, clientId: client.id, from: from, to: to);
  }
  var total = Duration.zero;
  for (final project in group.allProjects) {
    total += totalFor(doc, projectId: project.id, from: from, to: to);
  }
  return total;
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onAdd});

  final String title;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(child: Text(title, style: text.headlineMedium)),
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            key: const Key('newProjectHeaderButton'),
            customBorder: const CircleBorder(),
            onTap: onAdd,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.add, color: colors.brand),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);

    return TextField(
      key: const Key('projectsSearchField'),
      controller: controller,
      decoration: InputDecoration(
        hintText: l10n.searchProjectsHint,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: colors.subtle,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: colors.focusRing, width: 2),
        ),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({
    required this.session,
    required this.doc,
    required this.group,
    required this.from,
    required this.to,
  });

  final DocumentSession? session;
  final CirrhyDocument doc;
  final _ClientGroup group;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final client = group.client;
    final total = _groupTotal(doc, group, from, to);
    final summary = l10n.clientSummary(
      group.projectCount,
      formatDuration(total, l10n.localeName),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(Radii.xl),
              ),
              onTap: client == null || session == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ClientDetailScreen(
                          session: session!,
                          clientId: client.id,
                        ),
                      ),
                    ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.x4,
                  Space.x3,
                  Space.x4,
                  Space.x3,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.label,
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.x2),
                    Flexible(
                      child: Text(
                        summary,
                        textAlign: TextAlign.right,
                        style: text.labelSmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (group.visibleProjects.isNotEmpty)
            Divider(height: 1, thickness: 1, color: colors.border),
          for (var i = 0; i < group.visibleProjects.length; i++) ...[
            _ProjectRow(
              session: session,
              doc: doc,
              project: group.visibleProjects[i],
            ),
            if (i != group.visibleProjects.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: colors.border,
                indent: Space.x4,
                endIndent: Space.x4,
              ),
          ],
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.session,
    required this.doc,
    required this.project,
  });

  final DocumentSession? session;
  final CirrhyDocument doc;
  final Project project;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final taskCount = doc.tasks.values
        .where((t) => t.projectId == project.id && !t.archived)
        .length;

    return InkWell(
      onTap: session == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProjectDetailScreen(
                  session: session!,
                  projectId: project.id,
                ),
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x4,
          vertical: Space.x3,
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: parseProjectColor(project.color) ?? colors.brand,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium,
              ),
            ),
            const SizedBox(width: Space.x2),
            Text(
              l10n.taskCount(taskCount),
              style: text.labelSmall?.copyWith(color: colors.textMuted),
            ),
            const SizedBox(width: Space.x1),
            Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _ArchivedCard extends StatelessWidget {
  const _ArchivedCard({
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.clients,
    required this.projects,
    required this.onUnarchiveClient,
    required this.onUnarchiveProject,
  });

  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Client> clients;
  final List<Project> projects;
  final ValueChanged<Client> onUnarchiveClient;
  final ValueChanged<Project> onUnarchiveProject;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.subtle,
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('archivedSectionToggle'),
            borderRadius: BorderRadius.circular(Radii.xl),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.x4,
                vertical: Space.x3,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.archivedLabel,
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    l10n.archivedCount(count),
                    style: text.labelSmall?.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(width: Space.x1),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x4,
                0,
                Space.x4,
                Space.x3,
              ),
              child: Column(
                children: [
                  for (final client in clients)
                    _ArchivedRow(
                      name: client.name,
                      onUnarchive: () => onUnarchiveClient(client),
                    ),
                  for (final project in projects)
                    _ArchivedRow(
                      name: project.name,
                      onUnarchive: () => onUnarchiveProject(project),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({required this.name, required this.onUnarchive});

  final String name;
  final VoidCallback onUnarchive;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(color: colors.textMuted),
          ),
        ),
        TextButton(onPressed: onUnarchive, child: Text(l10n.unarchiveAction)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final style = Theme.of(context).textTheme.bodyLarge;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x16),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: style?.copyWith(color: colors.textMuted),
      ),
    );
  }
}
