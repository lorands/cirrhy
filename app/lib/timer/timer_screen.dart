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

import 'dart:async';

import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/document_session.dart';
import '../l10n/duration_format.dart';
import '../l10n/generated/app_localizations.dart';
import '../sync/foreign_timers_section.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/entity_chip.dart';
import '../widgets/entry_row.dart';
import 'start_timer_sheet.dart';

const _markAsset = 'assets/logo/cirrhy-mark.png';

/// The Timer tab: the running timer plus recent logged work.
///
/// Penpot "09 · Screens & Flow", boards B1 (idle) and B2 (running). Replaces
/// the stub `_TimerTab` that used to live in `app_shell.dart`.
///
/// [session] is nullable so a shell built without the app's real
/// dependencies — `const CirrhyApp()`'s own tests, and the moment before
/// first run has produced one — still renders something sane: an idle card
/// with a disabled Start button and the empty state, never a crash. Nothing
/// here mutates anything when [session] is null.
class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key, this.session, DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  final DocumentSession? session;

  /// Where the running card's ticking display reads "now" from. Defaults to
  /// the real wall clock, exactly like [DocumentSession]'s own clock —
  /// deliberately not `package:clock`, to stay in step with that existing
  /// convention rather than add a second one.
  ///
  /// This exists for tests: `flutter_test`'s `tester.pump(duration)` fakes
  /// `Timer`, so a periodic ticker still fires on schedule, but it does *not*
  /// fake `DateTime.now()` — a widget reading the real clock would tick zero
  /// seconds no matter how long a test pumps. Injecting the clock lets a test
  /// advance both together and see the display actually move.
  final DateTime Function() clock;

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  @override
  void initState() {
    super.initState();
    widget.session?.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(covariant TimerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session?.removeListener(_onSessionChanged);
      widget.session?.addListener(_onSessionChanged);
    }
  }

  @override
  void dispose() {
    widget.session?.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final entries = (session?.document ?? const CirrhyDocument.empty())
        .entriesByRecency();
    final myTimer = session?.myTimer;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.x4,
        Space.x6,
        Space.x4,
        Space.x8,
      ),
      children: [
        const _Header(),
        const SizedBox(height: Space.x6),
        if (myTimer == null)
          _IdleCard(
            onStart: session?.startTimer,
            // Null disables both taps too — nothing to open a picker into
            // without a session, exactly like the Start button below it.
            onSelectTask: session == null
                ? null
                : () => showStartTimerSheet(context, session),
          )
        else
          _RunningCard(
            timer: myTimer,
            project: session!.projectById(myTimer.projectId),
            client: session.clientById(
              session.projectById(myTimer.projectId)?.clientId,
            ),
            onStop: session.stopTimer,
            onEdit: () => showEditTimerSheet(context, session),
            clock: widget.clock,
          ),
        // F1: another device's timer arrived in a merge and has not been
        // acknowledged — reconciliation is surfaced, never resolved silently
        // (§3.6). Between the timer card and the list, per the mockup.
        if (session != null && session.hasUnacknowledgedForeignTimers) ...[
          const SizedBox(height: Space.x6),
          ForeignTimersSection(session: session, clock: widget.clock),
        ],
        const SizedBox(height: Space.x8),
        if (entries.isEmpty)
          const _EmptyState()
        else
          _EntryGroups(entries: entries, session: session),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(_markAsset, width: 30, height: 30),
        const SizedBox(width: Space.x2),
        Text(l10n.appTitle, style: text.headlineMedium),
      ],
    );
  }
}

/// The card shell shared by the idle and running states: a rounded surface,
/// hairline border and elevation, with room for a coloured accent bar on the
/// left edge. The shadow is painted on an outer, unclipped box — putting it
/// on the same decoration that gets clipped for the rounded corners would
/// clip the shadow away with it.
class _TimerCardShell extends StatelessWidget {
  const _TimerCardShell({required this.child, this.accentColor});

  final Widget child;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final radius = BorderRadius.circular(Radii.xl);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: Elevation.level1,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (accentColor != null)
                  Container(width: 4, color: accentColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.x5),
                    child: child,
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

class _IdleCard extends StatelessWidget {
  const _IdleCard({required this.onStart, required this.onSelectTask});

  /// Null disables the button — there is nothing to start into without a
  /// session.
  final VoidCallback? onStart;

  /// Opens the start-timer sheet (B3). Null makes the hint and chip inert,
  /// exactly like [onStart] being null.
  final VoidCallback? onSelectTask;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return _TimerCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelectTask,
            child: Text(
              l10n.timerIdleHint,
              style: text.bodyLarge?.copyWith(color: colors.textMuted),
            ),
          ),
          const SizedBox(height: Space.x3),
          // Material(transparency) rather than a bare InkWell: this card can
          // be pumped without a Scaffold ancestor (the existing screen tests
          // do exactly that), and InkWell alone throws without one.
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.full),
              onTap: onSelectTask,
              child: EntityChip(
                label: l10n.timerSelectTask,
                dotColor: colors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: Space.x5),
          Row(
            children: [
              Expanded(
                child: Text(
                  formatTimer(Duration.zero, l10n.localeName),
                  style: Type.timer.copyWith(color: colors.textMuted),
                ),
              ),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(l10n.timerStart),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RunningCard extends StatefulWidget {
  const _RunningCard({
    required this.timer,
    required this.project,
    required this.client,
    required this.onStop,
    required this.onEdit,
    required this.clock,
  });

  final RunningTimer timer;
  final Project? project;
  final Client? client;
  final VoidCallback onStop;

  /// Opens the edit-timer sheet — wired to the status line, description and
  /// chip, deliberately not to the timer row below them, so it can never
  /// compete with the Stop button's own tap target.
  final VoidCallback onEdit;
  final DateTime Function() clock;

  @override
  State<_RunningCard> createState() => _RunningCardState();
}

class _RunningCardState extends State<_RunningCard> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    // Ticks a rebuild every second; [build] recomputes the elapsed time from
    // the clock and the timer's own start each time, so nothing here
    // accumulates and a missed or delayed tick never drifts the readout.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final elapsed = widget.clock().toUtc().difference(widget.timer.startedAt);
    final description = widget.timer.description;
    final hasDescription = description.isNotEmpty;
    final project = widget.project;

    return _TimerCardShell(
      accentColor: colors.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Material(transparency) rather than a bare InkWell — same reason
          // as the idle card's chip: this can be pumped without a Scaffold
          // ancestor. Only the status line, description and chip sit inside
          // it; the timer readout and Stop button below stay outside, so the
          // two tap targets never overlap.
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onEdit,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colors.running,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: Space.x2),
                      Text(
                        l10n.timerRunning,
                        style: text.labelSmall?.copyWith(
                          color: colors.running,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.x2),
                  Text(
                    hasDescription ? description : l10n.timerNoDescription,
                    style: hasDescription
                        ? text.bodyLarge
                        : text.bodyLarge?.copyWith(color: colors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (project != null) ...[
                    const SizedBox(height: Space.x2),
                    ProjectChip(project: project, client: widget.client),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.x5),
          Row(
            children: [
              Expanded(
                child: Text(
                  formatTimer(elapsed, l10n.localeName),
                  style: Type.timer.copyWith(color: colors.textPrimary),
                ),
              ),
              _StopButton(onPressed: widget.onStop),
            ],
          ),
        ],
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);

    return Material(
      // No text label and no design-specified tooltip (unlike Start and the
      // run buttons) — a plain key so tests can still find it precisely.
      key: const Key('timerStopButton'),
      color: colors.dangerSubtle,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            // A plain dark square rather than an Icon glyph, matching the
            // design exactly — textPrimary rather than a literal near-black,
            // so it still reads against the dark scheme's dangerSubtle, which
            // has no mockup of its own yet.
            child: Container(width: 14, height: 14, color: colors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x16),
      child: Column(
        children: [
          Text(
            l10n.timerEmptyTitle,
            style: text.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.x2),
          Text(
            l10n.timerEmptyBody,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Splits [entries] — already newest-first — into day groups without
/// re-sorting: the local day of a UTC instant is a non-increasing function of
/// that instant for a fixed offset, so grouping by first appearance preserves
/// newest-day-first for free.
class _EntryGroups extends StatelessWidget {
  const _EntryGroups({required this.entries, required this.session});

  final List<TimeEntry> entries;
  final DocumentSession? session;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final groups = <DateTime, List<TimeEntry>>{};
    for (final entry in entries) {
      final local = entry.start.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      groups.putIfAbsent(day, () => []).add(entry);
    }

    final days = groups.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i != 0) const SizedBox(height: Space.x6),
          _DayGroup(
            day: days[i],
            today: today,
            yesterday: yesterday,
            entries: groups[days[i]]!,
            session: session,
          ),
        ],
      ],
    );
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.day,
    required this.today,
    required this.yesterday,
    required this.entries,
    required this.session,
  });

  final DateTime day;
  final DateTime today;
  final DateTime yesterday;
  final List<TimeEntry> entries;
  final DocumentSession? session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    final label = day == today
        ? l10n.timerToday
        : day == yesterday
        ? l10n.timerYesterday
        : DateFormat.MMMEd(l10n.localeName).format(day);

    // Only entries that are actually stopped contribute a duration.
    var total = Duration.zero;
    for (final entry in entries) {
      final stop = entry.stop;
      if (stop != null) total += stop.difference(entry.start);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: text.headlineSmall)),
            Text(
              formatDuration(total, l10n.localeName),
              style: Type.duration.copyWith(color: colors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: Space.x3),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(color: colors.border),
          ),
          // The clip exists for the newFromSync tint: a filled first or last
          // row would otherwise paint square corners over the rounded border.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.xl),
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  EntryRow(
                    entry: entries[i],
                    session: session,
                    // F2: rows the last refresh merged in are tinted until
                    // the next refresh recomputes the set — no timers, the
                    // mark just stops being true.
                    newFromSync:
                        session?.lastRefreshNewEntryIds.contains(
                          entries[i].id,
                        ) ??
                        false,
                  ),
                  if (i != entries.length - 1)
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
          ),
        ),
      ],
    );
  }
}
