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
import 'new_project_sheet.dart';
import 'project_detail_screen.dart';
import 'rename_dialog.dart';

/// Client detail (Penpot "09 · Screens & Flow", C2): stats, its projects, and
/// archiving.
class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({
    super.key,
    required this.session,
    required this.clientId,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final DocumentSession session;
  final String clientId;

  /// Where "now" comes from for both `modified` timestamps and the "this
  /// month" window — the same clock convention every other screen uses, kept
  /// injectable so tests can pin it.
  final DateTime Function() clock;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  bool _poppingForMissingClient = false;

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

  Future<void> _rename(Client client) async {
    final name = await showRenameDialog(context, currentName: client.name);
    if (name == null) return;
    await widget.session.put(
      Client(
        id: client.id,
        modified: widget.clock().toUtc(),
        name: name,
        archived: client.archived,
        importSource: client.importSource,
        externalId: client.externalId,
        history: client.history,
      ),
    );
  }

  Future<void> _archive(Client client) async {
    final navigator = Navigator.of(context);
    await widget.session.put(
      Client(
        id: client.id,
        modified: widget.clock().toUtc(),
        name: client.name,
        archived: true,
        importSource: client.importSource,
        externalId: client.externalId,
        history: client.history,
      ),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final client = widget.session.document.clients[widget.clientId];

    if (client == null) {
      // Deleted, archived-and-popped, or removed by a merge from another
      // device — nothing left to show here.
      if (!_poppingForMissingClient) {
        _poppingForMissingClient = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return const Scaffold(body: SizedBox.shrink());
    }

    final doc = widget.session.document;
    final (from, to) = currentMonthWindow(widget.clock());
    final thisMonth = totalFor(doc, clientId: client.id, from: from, to: to);
    final allTime = totalFor(doc, clientId: client.id);
    final projects =
        doc.projects.values
            .where((p) => !p.archived && p.clientId == client.id)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(
        title: Text(client.name),
        actions: [
          IconButton(
            key: const Key('clientRenameButton'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _rename(client),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Space.x6),
          children: [
            _StatsCard(l10n: l10n, thisMonth: thisMonth, allTime: allTime),
            const SizedBox(height: Space.x6),
            _SectionLabel(l10n.tabProjects),
            const SizedBox(height: Space.x2),
            _ProjectsCard(
              session: widget.session,
              client: client,
              projects: projects,
              from: from,
              to: to,
            ),
            const SizedBox(height: Space.x6),
            Center(
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: CirrhyTheme.of(context).danger,
                ),
                onPressed: () => _archive(client),
                child: Text(l10n.archiveClientAction),
              ),
            ),
            const SizedBox(height: Space.x2),
            Text(
              l10n.archiveNote,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: CirrhyTheme.of(context).textMuted,
              ),
            ),
          ],
        ),
      ),
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

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.l10n,
    required this.thisMonth,
    required this.allTime,
  });

  final AppLocalizations l10n;
  final Duration thisMonth;
  final Duration allTime;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Row(
          children: [
            Expanded(
              child: _StatColumn(
                label: l10n.thisMonthLabel,
                value: formatDuration(thisMonth, l10n.localeName),
              ),
            ),
            SizedBox(
              height: 40,
              child: VerticalDivider(color: colors.border, width: Space.x6),
            ),
            Expanded(
              child: _StatColumn(
                label: l10n.allTimeLabel,
                value: formatDuration(allTime, l10n.localeName),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(color: colors.textMuted)),
        const SizedBox(height: Space.x1),
        Text(value, style: Type.duration.copyWith(fontSize: 20)),
      ],
    );
  }
}

class _ProjectsCard extends StatelessWidget {
  const _ProjectsCard({
    required this.session,
    required this.client,
    required this.projects,
    required this.from,
    required this.to,
  });

  final DocumentSession session;
  final Client client;
  final List<Project> projects;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final doc = session.document;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          for (final project in projects) ...[
            _ProjectRow(
              session: session,
              project: project,
              doc: doc,
              from: from,
              to: to,
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: colors.border,
              indent: Space.x4,
              endIndent: Space.x4,
            ),
          ],
          InkWell(
            key: const Key('clientNewProjectRow'),
            onTap: () => showNewProjectSheet(
              context,
              session,
              initialClientId: client.id,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.x4,
                vertical: Space.x3,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 18, color: colors.brand),
                  const SizedBox(width: Space.x2),
                  Text(
                    l10n.newProjectAction,
                    style: text.bodyMedium?.copyWith(
                      color: colors.brand,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.session,
    required this.project,
    required this.doc,
    required this.from,
    required this.to,
  });

  final DocumentSession session;
  final Project project;
  final CirrhyDocument doc;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final taskCount = doc.tasks.values
        .where((t) => t.projectId == project.id && !t.archived)
        .length;
    final total = totalFor(doc, projectId: project.id, from: from, to: to);

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ProjectDetailScreen(session: session, projectId: project.id),
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
              l10n.projectSummary(
                taskCount,
                formatDuration(total, l10n.localeName),
              ),
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
