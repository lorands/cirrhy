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

import '../l10n/generated/app_localizations.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/entity_chip.dart';
import 'report_query.dart';

/// The custom range sheet (Penpot "09 · Screens & Flow", D4).
///
/// Returns the query moved onto the chosen window, or null if the sheet was
/// dismissed. Every route out of it — a preset or the date picker — lands on
/// [ReportRange.custom] with an explicit window, so the chevrons afterwards
/// step by whatever length was chosen.
///
/// **Deviation from the board, deliberate.** D4 draws a bespoke month
/// calendar; this uses Material's `showDateRangePicker` instead. That picker
/// is already translated into all five shipped languages, already knows each
/// locale's first day of week, and already handles the range-selection edge
/// cases. A hand-built calendar would have to re-earn all three, and date
/// arithmetic in a widget is exactly where date bugs live. The presets above
/// it are the board's, unchanged, and they are the fast path the board was
/// really designing for.
Future<ReportQuery?> showCustomRangeSheet(
  BuildContext context, {
  required ReportQuery query,
  required DateTime now,
  required int firstDayOfWeekIndex,
}) {
  return showModalBottomSheet<ReportQuery>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _CustomRangeSheet(
      query: query,
      now: now,
      firstDayOfWeekIndex: firstDayOfWeekIndex,
    ),
  );
}

/// Which preset a chip stands for. Kept as an enum rather than a closure so
/// the windows themselves are computed in one readable place below.
enum RangePreset { thisWeek, lastWeek, thisMonth, last30 }

/// The half-open local window a preset resolves to, relative to [now].
///
/// "This week" and "last week" go through [startOfWeek], so a Hungarian
/// device gets Monday-to-Sunday and an American one Sunday-to-Saturday
/// without either being hard-coded here.
///
/// "Last 30 days" is a rolling window ending with today included, not a
/// calendar month — 30 days back from today, plus today itself.
(DateTime from, DateTime to) presetWindow(
  RangePreset preset,
  DateTime now,
  int firstDayOfWeekIndex,
) {
  final today = startOfDay(now);
  switch (preset) {
    case RangePreset.thisWeek:
      final from = startOfWeek(today, firstDayOfWeekIndex);
      return (from, addDays(from, 7));
    case RangePreset.lastWeek:
      final from = addDays(startOfWeek(today, firstDayOfWeekIndex), -7);
      return (from, addDays(from, 7));
    case RangePreset.thisMonth:
      final from = startOfMonth(today);
      return (from, DateTime(from.year, from.month + 1));
    case RangePreset.last30:
      return (addDays(today, -29), addDays(today, 1));
  }
}

class _CustomRangeSheet extends StatelessWidget {
  const _CustomRangeSheet({
    required this.query,
    required this.now,
    required this.firstDayOfWeekIndex,
  });

  final ReportQuery query;
  final DateTime now;
  final int firstDayOfWeekIndex;

  bool _isCurrent(RangePreset preset) {
    if (query.range != ReportRange.custom) return false;
    final (from, to) = presetWindow(preset, now, firstDayOfWeekIndex);
    return query.customFrom == from && query.customTo == to;
  }

  void _apply(BuildContext context, RangePreset preset) {
    final (from, to) = presetWindow(preset, now, firstDayOfWeekIndex);
    Navigator.of(context).pop(query.withCustomWindow(from, to));
  }

  Future<void> _pickDates(BuildContext context) async {
    final (currentFrom, currentTo) = query.window(firstDayOfWeekIndex);
    final navigator = Navigator.of(context);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      // The picker's range is inclusive on both ends; every window in Cirrhy
      // is half-open. `to` is therefore one day past the last day shown, and
      // has to be converted in both directions.
      initialDateRange: DateTimeRange(
        start: currentFrom,
        end: addDays(currentTo, -1),
      ),
    );
    if (picked == null) return;
    navigator.pop(
      query.withCustomWindow(
        startOfDay(picked.start),
        addDays(startOfDay(picked.end), 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    final labels = {
      RangePreset.thisWeek: l10n.presetThisWeek,
      RangePreset.lastWeek: l10n.presetLastWeek,
      RangePreset.thisMonth: l10n.presetThisMonth,
      RangePreset.last30: l10n.presetLast30,
    };

    return DecoratedBox(
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
              Text(l10n.customRangeTitle, style: text.headlineSmall),
              const SizedBox(height: Space.x5),
              Wrap(
                spacing: Space.x2,
                runSpacing: Space.x2,
                children: [
                  for (final preset in RangePreset.values)
                    SelectableChip(
                      key: Key('preset-${preset.name}'),
                      label: labels[preset]!,
                      selected: _isCurrent(preset),
                      onTap: () => _apply(context, preset),
                    ),
                ],
              ),
              const SizedBox(height: Space.x5),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const Key('pickDatesRow'),
                  borderRadius: BorderRadius.circular(Radii.md),
                  onTap: () => _pickDates(context),
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
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: colors.textMuted,
                        ),
                        const SizedBox(width: Space.x3),
                        Expanded(
                          child: Text(
                            l10n.pickDatesAction,
                            style: text.bodyLarge,
                          ),
                        ),
                        Icon(Icons.chevron_right, color: colors.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
