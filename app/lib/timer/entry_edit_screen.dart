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
import '../widgets/entity_chip.dart';
import 'task_picker_sheet.dart';

/// Entry — edit & history (Penpot "09 · Screens & Flow", B5).
///
/// The screen this app's two core invariants are built around, per DESIGN.md
/// §3.1 and §3.4: [TimeEntry.start] and [TimeEntry.stop] are edited here as
/// one field-set and saved as a single [TimeEntry] — never independently
/// persisted — and every save goes through [DocumentSession.put], whose
/// read-merge-write demotes whatever was on disk into that record's own
/// `history` rather than discarding it. This screen never hand-builds a
/// history list; it only ever reads the one the engine already produced.
///
/// A null [entryId] is the manual-add flow — the entry the user forgot to
/// track and is reconstructing from memory. Same form, but Save mints a new
/// [TimeEntry] instead of replacing one, and everything that presumes a
/// stored record (Delete, History, the vanished-record pop) stays out of the
/// tree. 09 has no board for this; the form is B5's, the affordance that
/// opens it follows the projects header's + button.
class EntryEditScreen extends StatefulWidget {
  const EntryEditScreen({
    super.key,
    required this.session,
    required this.entryId,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final DocumentSession session;

  /// The entry being edited, or null to create a new one.
  final String? entryId;

  /// Where "now" comes from for `modified` timestamps on save/restore.
  /// Overridable for tests, exactly like [DocumentSession]'s own clock.
  final DateTime Function() clock;

  @override
  State<EntryEditScreen> createState() => _EntryEditScreenState();
}

class _EntryEditScreenState extends State<EntryEditScreen> {
  final _description = TextEditingController();

  // Edited state, independent of whatever the session's document happens to
  // hold at any given rebuild — an external merge landing while this screen
  // is open must never overwrite an in-progress, unsaved edit. Only two
  // things ever assign these: [_loadFrom] (initial load and after a
  // Restore) and the field-specific handlers below.
  DateTime _start = DateTime.now().toUtc();
  DateTime? _stop;
  String? _projectId;
  String? _taskId;

  bool _poppingForMissingEntry = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    final entryId = widget.entryId;
    if (entryId == null) {
      // Manual add: start == stop == now, a deliberately zero-length prefill.
      // Any guessed duration would read as data and get saved by accident;
      // 0:00 is honestly wrong, which is what prompts the user to set both
      // times. Stop is never null here — only a real timer may be open.
      final now = widget.clock().toUtc();
      _start = now;
      _stop = now;
    } else {
      final entry = widget.session.document.entries[entryId];
      if (entry != null) _loadFrom(entry);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _description.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    // Deliberately just a rebuild: [build] re-reads the current entry for
    // display (the history list, the vanished-record check) without
    // touching the fields above, so an unrelated session notification never
    // clobbers what the user is mid-way through typing.
    if (mounted) setState(() {});
  }

  void _loadFrom(TimeEntry entry) {
    _description.text = entry.description;
    _start = entry.start;
    _stop = entry.stop;
    _projectId = entry.projectId;
    _taskId = entry.taskId;
  }

  // ---- Derived duration / overnight handling -------------------------

  /// Whether [stop], compared to [start], reads as "ends the next day":
  /// DESIGN.md's overnight entries are real, and clock-only comparisons
  /// don't have negative durations, only later calendar days.
  bool get _isOvernight {
    final stop = _stop;
    if (stop == null) return false;
    final startDay = _dateOnly(_start.toLocal());
    final stopDay = _dateOnly(stop.toLocal());
    return stopDay.isAfter(startDay);
  }

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  // ---- Field edits ------------------------------------------------------

  Future<void> _pickTask() async {
    final choice = await showTaskPicker(context, widget.session);
    if (choice != null && mounted) {
      setState(() {
        _taskId = choice.taskId;
        _projectId = choice.projectId;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = widget.clock();
    final picked = await showDatePicker(
      context: context,
      initialDate: _start.toLocal(),
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null || !mounted) return;
    // Both start and stop move by the same number of days, so the relative
    // offset between them — including a genuinely multi-day span — survives
    // untouched. DESIGN.md §3.1: start and stop travel as a unit.
    final delta = _dateOnly(
      picked,
    ).difference(_dateOnly(_start.toLocal())).inDays;
    if (delta == 0) return;
    setState(() {
      _start = _start.add(Duration(days: delta));
      final stop = _stop;
      if (stop != null) _stop = stop.add(Duration(days: delta));
    });
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start.toLocal()),
    );
    if (picked == null || !mounted) return;
    final local = _start.toLocal();
    setState(() {
      _start = DateTime(
        local.year,
        local.month,
        local.day,
        picked.hour,
        picked.minute,
      ).toUtc();
    });
  }

  Future<void> _pickStop() async {
    final stop = _stop;
    if (stop == null) return; // Inert: nothing to edit on an open entry.
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(stop.toLocal()),
    );
    if (picked == null || !mounted) return;
    final local = stop.toLocal();
    var candidate = DateTime(
      local.year,
      local.month,
      local.day,
      picked.hour,
      picked.minute,
    ).toUtc();
    // The edit that makes overnight entries expressible: a stop clock-time
    // at or before start's, on stop's own day, is never a real negative
    // interval — it means the entry runs into the next calendar day.
    if (!candidate.isAfter(_start)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    setState(() => _stop = candidate);
  }

  // ---- Save / delete / restore -------------------------------------------

  /// The location-change rule shared by Save and Restore (DESIGN.md §3.5):
  /// re-assigning project/task is a distinct event from editing anything
  /// else, so it alone bumps `locationChanged`.
  DateTime _locationChangedFor(
    TimeEntry current,
    String? newProjectId,
    String? newTaskId,
    DateTime now,
  ) {
    final relocated =
        newProjectId != current.projectId || newTaskId != current.taskId;
    return relocated ? now : current.locationChanged;
  }

  Future<void> _save() async {
    final now = widget.clock().toUtc();
    final entryId = widget.entryId;
    if (entryId == null) {
      final navigator = Navigator.of(context);
      await widget.session.put(
        TimeEntry(
          id: uuidV4(),
          modified: now,
          start: _start,
          stop: _stop,
          projectId: _projectId,
          // Born here, so its location was chosen now — not inherited.
          locationChanged: now,
          taskId: _taskId,
          description: _description.text.trim(),
        ),
      );
      navigator.pop();
      return;
    }
    final current = widget.session.document.entries[entryId];
    if (current == null) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    final updated = TimeEntry(
      id: current.id,
      modified: now,
      start: _start,
      stop: _stop,
      projectId: _projectId,
      locationChanged: _locationChangedFor(current, _projectId, _taskId, now),
      taskId: _taskId,
      description: _description.text.trim(),
      billable: current.billable,
      history: current.history,
    );
    final navigator = Navigator.of(context);
    await widget.session.put(updated);
    navigator.pop();
  }

  Future<void> _confirmDelete() async {
    final entryId = widget.entryId;
    if (entryId == null) return; // Create mode renders no Delete button.
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteEntryConfirmTitle),
        content: Text(l10n.deleteEntryConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelAction),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: colors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    await widget.session.delete(entryId);
    navigator.pop();
  }

  Future<void> _restore(RecordVersion version) async {
    final current = widget.session.document.entries[widget.entryId];
    if (current == null) return;
    final now = widget.clock().toUtc();
    final fields = version.fields;
    final restoredProjectId = fields['projectId'] as String?;
    final restoredTaskId = fields['taskId'] as String?;
    final restored = TimeEntry(
      id: current.id,
      modified: now,
      start: DateTime.parse(fields['start'] as String).toUtc(),
      stop: fields['stop'] == null
          ? null
          : DateTime.parse(fields['stop'] as String).toUtc(),
      projectId: restoredProjectId,
      locationChanged: _locationChangedFor(
        current,
        restoredProjectId,
        restoredTaskId,
        now,
      ),
      taskId: restoredTaskId,
      description: (fields['description'] as String?) ?? '',
      billable: fields['billable'] == true,
      history: current.history,
    );
    await widget.session.put(restored);
    if (mounted) setState(() => _loadFrom(restored));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entryId = widget.entryId;
    final entry = entryId == null
        ? null
        : widget.session.document.entries[entryId];

    if (entryId != null && entry == null) {
      // Deleted out from under us — by this screen's own Delete action, or a
      // merge from another device. Either way there is nothing left to edit;
      // pop on the next frame rather than mid-build. A create-mode screen
      // never lands here: it has no stored record to lose.
      if (!_poppingForMissingEntry) {
        _poppingForMissingEntry = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(entryId == null ? l10n.addEntryTitle : l10n.editEntryTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Space.x6),
          children: [
            _FieldLabel(l10n.descriptionLabel),
            const SizedBox(height: Space.x1),
            TextField(controller: _description),
            const SizedBox(height: Space.x5),
            _FieldLabel(l10n.taskLabel),
            const SizedBox(height: Space.x1),
            _TaskField(
              session: widget.session,
              taskId: _taskId,
              projectId: _projectId,
              onTap: _pickTask,
            ),
            const SizedBox(height: Space.x5),
            _FieldLabel(l10n.dateLabel),
            const SizedBox(height: Space.x1),
            _FieldBox(
              onTap: _pickDate,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat.yMMMMEEEEd(
                        l10n.localeName,
                      ).format(_start.toLocal()),
                    ),
                  ),
                  Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: CirrhyTheme.of(context).textMuted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.x5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _TimeField(
                    label: l10n.startLabel,
                    time: _start,
                    onTap: _pickStart,
                  ),
                ),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: _TimeField(
                    label: l10n.stopLabel,
                    time: _stop,
                    onTap: _pickStop,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.x5),
            _DurationRow(start: _start, stop: _stop, overnight: _isOvernight),
            const SizedBox(height: Space.x6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: Text(l10n.saveAction),
              ),
            ),
            if (entry != null) ...[
              const SizedBox(height: Space.x4),
              Center(
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: CirrhyTheme.of(context).danger,
                  ),
                  onPressed: _confirmDelete,
                  child: Text(l10n.deleteEntryAction),
                ),
              ),
            ],
            if (entry != null && entry.history.isNotEmpty) ...[
              const SizedBox(height: Space.x6),
              _FieldLabel(l10n.historyLabel),
              const SizedBox(height: Space.x3),
              _HistoryCard(history: entry.history, onRestore: _restore),
              const SizedBox(height: Space.x3),
              Text(
                l10n.historyFootnote,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CirrhyTheme.of(context).textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

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

/// A bordered, `Radii.md` row matching the app's `InputDecoration` look, for
/// fields that open a picker rather than accept direct text input.
class _FieldBox extends StatelessWidget {
  const _FieldBox({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
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
          child: child,
        ),
      ),
    );
  }
}

/// The TASK selector row: the chosen task's chip path, or the muted
/// placeholder, plus a chevron — the same shape as the start-timer sheet's
/// own task selector (B3), reused here rather than re-invented.
class _TaskField extends StatelessWidget {
  const _TaskField({
    required this.session,
    required this.taskId,
    required this.projectId,
    required this.onTap,
  });

  final DocumentSession session;
  final String? taskId;

  /// The entry's own project — the source of truth when [taskId] is null,
  /// which is the valid "project chosen, no task" shape (DESIGN.md allows a
  /// [TimeEntry] with a project and no task).
  final String? projectId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final task = taskId == null ? null : session.taskById(taskId);
    final project = session.projectById(task?.projectId ?? projectId);
    final client = session.clientById(project?.clientId);

    Widget content;
    if (task == null && project == null) {
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

    return _FieldBox(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(child: content),
          Icon(Icons.expand_more, color: colors.textMuted),
        ],
      ),
    );
  }
}

/// A START or STOP field. `time == null` renders an inert em dash — the
/// still-open entry case, another device's timer arrived via merge.
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final DateTime? time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final t = time;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: Space.x1),
        _FieldBox(
          onTap: t == null ? null : onTap,
          child: Text(
            t == null
                ? '—'
                : DateFormat.Hm(l10n.localeName).format(t.toLocal()),
            style: Type.duration.copyWith(
              color: t == null ? colors.textMuted : colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _DurationRow extends StatelessWidget {
  const _DurationRow({
    required this.start,
    required this.stop,
    required this.overnight,
  });

  final DateTime start;
  final DateTime? stop;
  final bool overnight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final s = stop;
    final durationText = s == null
        ? '—'
        : formatDuration(s.difference(start), l10n.localeName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(l10n.durationLabel),
        const SizedBox(height: Space.x1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              durationText,
              style: Type.duration.copyWith(
                fontSize: 24,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Text(
                overnight ? l10n.stopNextDay : l10n.startStopUnit,
                style: text.labelSmall?.copyWith(
                  color: overnight ? colors.warning : colors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.history, required this.onRestore});

  final List<RecordVersion> history;
  final void Function(RecordVersion version) onRestore;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    // Newest-first is already the engine's invariant (RecordVersion sorts
    // that way), but re-sorting here is cheap and keeps this rendering
    // correct even if that invariant ever changes underneath it.
    final versions = [...history]..sort();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < versions.length; i++) ...[
            _HistoryRow(version: versions[i], onRestore: onRestore),
            if (i != versions.length - 1)
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

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.version, required this.onRestore});

  final RecordVersion version;
  final void Function(RecordVersion version) onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x4,
        vertical: Space.x3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history, size: 18, color: colors.textSecondary),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _summaryOf(version.fields, l10n.localeName),
                  style: text.bodyMedium,
                ),
                const SizedBox(height: Space.x1),
                Text(
                  DateFormat.yMMMEd(
                    l10n.localeName,
                  ).add_Hm().format(version.modified.toLocal()),
                  style: text.labelSmall?.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.x2),
          TextButton(
            onPressed: () => onRestore(version),
            child: Text(l10n.restoreAction),
          ),
        ],
      ),
    );
  }
}

/// The version's description if it had one, else its start–stop range —
/// built straight from the snapshot's raw field map (DESIGN.md §3.4), never
/// from a decoded [TimeEntry], since a history entry is not one.
String _summaryOf(Map<String, Object?> fields, String localeName) {
  final description = (fields['description'] as String?) ?? '';
  if (description.isNotEmpty) return description;

  final start = DateTime.parse(fields['start'] as String).toLocal();
  final hm = DateFormat.Hm(localeName);
  final stopRaw = fields['stop'] as String?;
  if (stopRaw == null) return '${hm.format(start)} – …';
  return '${hm.format(start)} – ${hm.format(DateTime.parse(stopRaw).toLocal())}';
}
