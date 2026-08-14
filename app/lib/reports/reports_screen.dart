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
import '../data/document_views.dart';
import '../l10n/duration_format.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/entity_chip.dart';
import '../widgets/entry_row.dart';
import 'custom_range_sheet.dart';
import 'range_format.dart';
import 'report_filters_sheet.dart';
import 'report_query.dart';

/// The Reports tab: Penpot "09 · Screens & Flow", boards D1 (summary) and D3
/// (entries). One screen, one [ReportQuery]; the view segment swaps the body
/// below the range row and nothing else, because the window and the filters
/// are the same question in both.
///
/// [session] is nullable for the same reason it is on the timer screen — a
/// shell built without the app's real dependencies still has to render
/// something rather than crash. With no session the document is empty, which
/// takes the same path as a range with nothing in it.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.session, DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  final DocumentSession? session;

  /// Where "today" comes from: which day the chart highlights, which window
  /// the screen opens on, and how far forward the chevron may go. Injected
  /// exactly as [TimerScreen] injects it, because `tester.pump` fakes timers
  /// but never `DateTime.now()`.
  final DateTime Function() clock;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late ReportQuery _query;

  @override
  void initState() {
    super.initState();
    _query = ReportQuery.at(widget.clock());
    widget.session?.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(covariant ReportsScreen oldWidget) {
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

  int get _firstDayOfWeek =>
      MaterialLocalizations.of(context).firstDayOfWeekIndex;

  Future<void> _chooseRange(ReportRange next) async {
    if (next == ReportRange.custom) {
      await _openCustomRange();
      return;
    }
    setState(() => _query = _query.withRange(next));
  }

  Future<void> _openCustomRange() async {
    final chosen = await showCustomRangeSheet(
      context,
      query: _query,
      now: widget.clock(),
      firstDayOfWeekIndex: _firstDayOfWeek,
    );
    // Dismissing the sheet leaves the current range alone — tapping Custom
    // and changing your mind must not strand the screen on a window nobody
    // chose.
    if (chosen != null && mounted) setState(() => _query = chosen);
  }

  Future<void> _openFilters() async {
    final session = widget.session;
    if (session == null) return;
    final (from, to) = _query.window(_firstDayOfWeek);
    final chosen = await showReportFiltersSheet(
      context,
      session: session,
      query: _query,
      from: from,
      to: to,
    );
    if (chosen != null && mounted) setState(() => _query = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = widget.session;
    final doc = session?.document ?? const CirrhyDocument.empty();
    final firstDayOfWeek = _firstDayOfWeek;
    final (from, to) = _query.window(firstDayOfWeek);

    final entries = entriesInRange(
      doc,
      from: from,
      to: to,
      clientIds: _query.clientIds,
      projectIds: _query.projectIds,
      taskIds: _query.taskIds,
      billableOnly: _query.billableOnly,
    );
    final total = sumOf(entries);
    final rangeLabel = formatReportRange(
      _query.range,
      from,
      to,
      l10n.localeName,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.x4,
        Space.x6,
        Space.x4,
        Space.x8,
      ),
      children: [
        _Header(
          filtered: _query.hasFilters,
          onFilters: session == null ? null : _openFilters,
        ),
        const SizedBox(height: Space.x5),
        _Segmented<ReportRange>(
          value: _query.range,
          onSelect: _chooseRange,
          segments: [
            (ReportRange.day, l10n.rangeDay),
            (ReportRange.week, l10n.rangeWeek),
            (ReportRange.month, l10n.rangeMonth),
            (ReportRange.custom, l10n.rangeCustom),
          ],
        ),
        const SizedBox(height: Space.x4),
        Center(
          child: SizedBox(
            width: 198,
            child: _Segmented<ReportView>(
              value: _query.view,
              onSelect: (view) =>
                  setState(() => _query = _query.copyWith(view: view)),
              segments: [
                (ReportView.summary, l10n.summaryView),
                (ReportView.entries, l10n.entriesView),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.x2),
        _RangeRow(
          label: rangeLabel,
          onPrevious: () => setState(() => _query = _query.shifted(-1)),
          onNext: _query.canAdvance(widget.clock(), firstDayOfWeek)
              ? () => setState(() => _query = _query.shifted(1))
              : null,
        ),
        if (entries.isEmpty)
          const _EmptyRange()
        else if (_query.view == ReportView.summary)
          ..._summary(context, doc, entries, total, from, to)
        else
          ..._entries(context, entries, total, rangeLabel),
      ],
    );
  }

  List<Widget> _summary(
    BuildContext context,
    CirrhyDocument doc,
    List<TimeEntry> entries,
    Duration total,
    DateTime from,
    DateTime to,
  ) {
    final l10n = AppLocalizations.of(context);
    final summary = _filterSummary(doc, _query, l10n);

    return [
      const SizedBox(height: Space.x5),
      _TotalBlock(total: total),
      const SizedBox(height: Space.x5),
      _ChartCard(
        days: daysInWindow(from, to),
        totals: dailyTotals(entries),
        today: startOfDay(widget.clock()),
      ),
      const SizedBox(height: Space.x6),
      _SectionLabel(l10n.byProjectLabel),
      const SizedBox(height: Space.x3),
      _ProjectBreakdown(doc: doc, totals: projectTotals(entries)),
      if (summary != null) ...[
        const SizedBox(height: Space.x3),
        _MutedNote(l10n.filteredNote(summary)),
      ],
    ];
  }

  List<Widget> _entries(
    BuildContext context,
    List<TimeEntry> entries,
    Duration total,
    String rangeLabel,
  ) {
    final l10n = AppLocalizations.of(context);
    final session = widget.session;

    // Already newest-first out of `entriesInRange`, and the local day of an
    // instant is non-increasing along that order, so grouping by first
    // appearance keeps the newest day on top without a second sort.
    final groups = <DateTime, List<TimeEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(localDay(entry.start), () => []).add(entry);
    }
    final days = groups.keys.toList();

    final caption = [
      rangeLabel,
      l10n.entriesSummary(entries.length),
      formatDuration(total, l10n.localeName),
    ].join(' · ');

    return [
      const SizedBox(height: Space.x3),
      _MutedNote(caption, align: TextAlign.center),
      const SizedBox(height: Space.x5),
      for (var i = 0; i < days.length; i++) ...[
        if (i != 0) const SizedBox(height: Space.x6),
        _DayGroup(day: days[i], entries: groups[days[i]]!, session: session),
      ],
      const SizedBox(height: Space.x6),
      _MutedNote(l10n.entriesFootnote),
    ];
  }
}

/// The plain-language "what am I looking at" line under the by-project card.
///
/// Names, comma-joined, sorted inside each axis so the same filter always
/// reads the same way — the sets themselves are in whatever order the chips
/// were tapped.
String? _filterSummary(
  CirrhyDocument doc,
  ReportQuery query,
  AppLocalizations l10n,
) {
  List<String> named(Set<String> ids, String? Function(String id) lookup) {
    final names = <String>[];
    for (final id in ids) {
      final name = lookup(id);
      if (name != null) names.add(name);
    }
    return names..sort();
  }

  final parts = [
    ...named(query.clientIds, (id) => doc.clients[id]?.name),
    ...named(query.projectIds, (id) => doc.projects[id]?.name),
    ...named(query.taskIds, (id) => doc.tasks[id]?.name),
    if (query.billableOnly) l10n.billableOnly,
  ];
  return parts.isEmpty ? null : parts.join(', ');
}

class _Header extends StatelessWidget {
  const _Header({required this.filtered, required this.onFilters});

  /// Whether any filter is active — the badge dot on the button.
  final bool filtered;
  final VoidCallback? onFilters;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(child: Text(l10n.tabReports, style: text.headlineMedium)),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Tooltip(
              message: l10n.filtersTitle,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const Key('reportsFilterButton'),
                  customBorder: const CircleBorder(),
                  onTap: onFilters,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(Icons.tune, color: colors.textSecondary),
                  ),
                ),
              ),
            ),
            if (filtered)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  key: const Key('reportsFilterBadge'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.brand,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The pill track with one white active segment, used for both the range and
/// the view choice. Generic over the value so neither copy can drift.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.segments,
    required this.value,
    required this.onSelect,
  });

  final List<(T value, String label)> segments;
  final T value;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colors.subtle,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Row(
        children: [
          for (final (segmentValue, label) in segments)
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: Key('segment-$segmentValue'),
                  borderRadius: BorderRadius.circular(Radii.full),
                  onTap: () => onSelect(segmentValue),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: segmentValue == value
                        ? BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(Radii.full),
                          )
                        : null,
                    child: Center(
                      child: Text(
                        label,
                        style: text.labelLarge?.copyWith(
                          color: segmentValue == value
                              ? colors.textPrimary
                              : colors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RangeRow extends StatelessWidget {
  const _RangeRow({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrevious;

  /// Null once the next window would start in the future, which can only ever
  /// be empty.
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        IconButton(
          key: const Key('reportsPreviousRange'),
          onPressed: onPrevious,
          color: colors.textMuted,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: text.bodyMedium,
          ),
        ),
        IconButton(
          key: const Key('reportsNextRange'),
          onPressed: onNext,
          color: colors.textMuted,
          disabledColor: colors.borderStrong,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _TotalBlock extends StatelessWidget {
  const _TotalBlock({required this.total});

  final Duration total;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        Text(
          l10n.totalLabel,
          style: text.labelSmall?.copyWith(color: colors.textMuted),
        ),
        Text(
          formatDuration(total, l10n.localeName),
          style: Type.timer.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}

/// One bar per local day in the window.
///
/// A plain `Row` of `Expanded` columns rather than a `CustomPaint`: the chart
/// is a bar per day and nothing else, so there is no curve, no axis and no
/// hit-testing that painting would buy. Laying it out means it scales to any
/// width — 7 bars on a phone, 31 on a desktop — for free.
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.days,
    required this.totals,
    required this.today,
  });

  final List<DateTime> days;
  final Map<DateTime, Duration> totals;
  final DateTime today;

  /// The tallest bar. The board measures 96 from baseline to the top of its
  /// tallest bar, and the caption above it needs the rest of the card.
  static const double _maxBar = 96;

  /// A day with time on it never draws thinner than this, so a ten-minute
  /// Tuesday next to an eight-hour Monday is still visibly a bar.
  static const double _minBar = 6;

  /// A day with nothing on it draws this instead — present, obviously empty.
  static const double _stubBar = 4;

  /// How far the bar fills its column. The board's 28px bar in a 45px column.
  static const double _barWidthFactor = 0.62;

  /// The board fills quiet days with brand100, which the semantic token set
  /// does not carry. Mixing brandEmphasis into the card's own surface lands
  /// on the same colour in the light scheme and — unlike a fixed pale green —
  /// stays visible against the dark scheme's surface too.
  static const double _quietBarMix = 0.22;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    var longest = Duration.zero;
    for (final day in days) {
      final total = totals[day] ?? Duration.zero;
      if (total > longest) longest = total;
    }

    // Above roughly a week the captions stop fitting between the bars, and a
    // month of them would be unreadable anyway.
    final showValues = days.length <= 7;
    // Weekday initials for a week; day-of-month numbers once there are more
    // days than initials can distinguish, thinned so they do not collide.
    final weekdayLabels = days.length <= 7;
    final labelStride = days.length > 14 ? 5 : 1;

    final quiet = Color.lerp(
      colors.surface,
      colors.brandEmphasis,
      _quietBarMix,
    )!;
    final weekday = DateFormat.E(l10n.localeName);
    final dayOfMonth = DateFormat.d(l10n.localeName);

    return _Card(
      padding: const EdgeInsets.fromLTRB(
        Space.x5,
        Space.x5,
        Space.x5,
        Space.x4,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in days)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showValues)
                        SizedBox(
                          height: 18,
                          child: Center(
                            child: Text(
                              (totals[day] ?? Duration.zero) == Duration.zero
                                  ? ''
                                  : formatDuration(
                                      totals[day]!,
                                      l10n.localeName,
                                    ),
                              style: text.labelSmall?.copyWith(
                                color: day == today
                                    ? colors.brand
                                    : colors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                            ),
                          ),
                        ),
                      SizedBox(
                        height: _maxBar,
                        // Align sits between the slot and the bar so the bar
                        // is laid out under *loose* height constraints. A
                        // SizedBox constrains height tightly, and a bar given
                        // a tight height is every bar the same height — a
                        // solid block instead of a chart.
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            widthFactor: _barWidthFactor,
                            child: _Bar(
                              // Keyed by the day it stands for: a test can
                              // then measure one bar rather than counting
                              // anonymous boxes.
                              key: ValueKey(
                                'chartBar-${day.year}-${day.month}-${day.day}',
                              ),
                              height: _barHeight(totals[day], longest),
                              color:
                                  (totals[day] ?? Duration.zero) ==
                                      Duration.zero
                                  ? colors.subtle
                                  : day == today
                                  ? colors.brand
                                  : quiet,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          Container(height: 1, color: colors.border),
          const SizedBox(height: Space.x2),
          Row(
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      i % labelStride != 0
                          ? ''
                          : weekdayLabels
                          ? _initial(weekday.format(days[i]))
                          : dayOfMonth.format(days[i]),
                      style: text.labelSmall?.copyWith(
                        color: days[i] == today
                            ? colors.brand
                            : colors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static double _barHeight(Duration? total, Duration longest) {
    final value = total ?? Duration.zero;
    if (value == Duration.zero) return _stubBar;
    if (longest == Duration.zero) return _minBar;
    final scaled = _maxBar * (value.inSeconds / longest.inSeconds);
    return scaled < _minBar ? _minBar : scaled;
  }

  /// The first letter of a locale's weekday name — "H" for hétfő, "M" for
  /// Monday. Taken from `DateFormat.E` rather than an alphabet of our own, so
  /// a sixth language costs nothing here either.
  static String _initial(String name) =>
      name.isEmpty ? '' : name.substring(0, 1);
}

class _Bar extends StatelessWidget {
  const _Bar({super.key, required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color,
        // Rounded at the top only: the bottom sits on the baseline hairline,
        // and a rounded foot would lift it off.
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.xs),
        ),
      ),
    );
  }
}

/// The window's total split per project, longest first.
class _ProjectBreakdown extends StatelessWidget {
  const _ProjectBreakdown({required this.doc, required this.totals});

  final CirrhyDocument doc;

  /// Keyed by project id; the null key is time logged against no project.
  final Map<String?, Duration> totals;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);

    final rows = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final longest = rows.isEmpty ? Duration.zero : rows.first.value;

    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _ProjectRow(
              // A project deleted or archived out from under logged time is
              // still time that was tracked, so it falls back to the same
              // heading as time with no project at all rather than vanishing.
              name: doc.projects[rows[i].key]?.name ?? l10n.noProjectLabel,
              color:
                  parseProjectColor(doc.projects[rows[i].key]?.color) ??
                  colors.textMuted,
              total: rows[i].value,
              fraction: longest == Duration.zero
                  ? 0
                  : rows[i].value.inSeconds / longest.inSeconds,
            ),
            if (i != rows.length - 1)
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
    required this.name,
    required this.color,
    required this.total,
    required this.fraction,
  });

  final String name;
  final Color color;
  final Duration total;
  final double fraction;

  /// Dot plus its gap: what the progress bar is indented by so it lines up
  /// under the name rather than under the dot.
  static const double _nameInset = 10 + Space.x3;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Text(
                  name,
                  style: text.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Space.x3),
              Text(
                formatDuration(total, l10n.localeName),
                style: Type.duration.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: Space.x2),
          Padding(
            padding: const EdgeInsets.only(left: _nameInset),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.xs),
              child: Container(
                height: 6,
                color: colors.subtle,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: ColoredBox(color: color),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A day of entries in the entries view (D3): the day's own heading and total
/// above a card of shared [EntryRow]s.
class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.day,
    required this.entries,
    required this.session,
  });

  final DateTime day;
  final List<TimeEntry> entries;
  final DocumentSession? session;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                // Always the date, never "Today" — a report is read at a
                // distance from the day it covers, and the timer screen's
                // relative headings would be a riddle three weeks back.
                DateFormat.MMMEd(l10n.localeName).format(day),
                style: text.headlineSmall,
              ),
            ),
            Text(
              formatDuration(sumOf(entries), l10n.localeName),
              style: Type.duration.copyWith(color: colors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: Space.x3),
        _Card(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                EntryRow(entry: entries[i], session: session),
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
      ],
    );
  }
}

/// The white, hairline-bordered card every block on this screen sits in.
class _Card extends StatelessWidget {
  const _Card({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: colors.border),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(color: colors.textMuted),
    );
  }
}

class _MutedNote extends StatelessWidget {
  const _MutedNote(this.text, {this.align = TextAlign.start});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    return Text(
      text,
      textAlign: align,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: colors.textMuted),
    );
  }
}

class _EmptyRange extends StatelessWidget {
  const _EmptyRange();

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x16),
      child: Text(
        l10n.reportsEmpty,
        textAlign: TextAlign.center,
        style: text.bodyMedium?.copyWith(color: colors.textMuted),
      ),
    );
  }
}
