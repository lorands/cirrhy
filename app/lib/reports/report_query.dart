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

/// What the reports screen is currently asking for, and the date arithmetic
/// that answers it.
///
/// Deliberately Flutter-free: every rule here — which week a day belongs to,
/// what "next month" means in December, how far a custom range jumps — is
/// arithmetic that wants unit tests rather than a pumped widget. The screen
/// supplies the two things this file refuses to guess: the current time and
/// the locale's first day of the week.
library;

/// The four shapes a report window can take, matching D1's segmented control.
enum ReportRange { day, week, month, custom }

/// Summary (D1) or the entry list (D3). The same query drives both.
enum ReportView { summary, entries }

/// Midnight of the local calendar day [instant] falls on.
DateTime startOfDay(DateTime instant) {
  final local = instant.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// [days] later (or earlier) than [day], as a local midnight.
///
/// Built through the [DateTime] constructor rather than by adding a
/// `Duration`: a `Duration` is an exact number of hours, so adding one across
/// a daylight-saving boundary lands on 23:00 or 01:00 of the neighbouring
/// day. Asking the constructor for "the 32nd of March" instead always
/// normalises to midnight of the right calendar day.
DateTime addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// The first day of the local calendar month [day] falls in.
DateTime startOfMonth(DateTime day) => DateTime(day.year, day.month);

/// The start of the week [day] falls in, for a locale whose week starts on
/// [firstDayOfWeekIndex] (0 = Sunday … 6 = Saturday, as
/// `MaterialLocalizations` numbers it).
///
/// Hungarian weeks start on Monday and American ones on Sunday, and a report
/// that disagrees with the calendar on the wall is wrong even when its
/// arithmetic is right — so this is never hard-coded.
DateTime startOfWeek(DateTime day, int firstDayOfWeekIndex) {
  // DateTime numbers Monday 1 … Sunday 7; `% 7` re-bases it to Sunday 0,
  // which is the numbering MaterialLocalizations uses.
  final sundayIndex = day.weekday % 7;
  // Dart's `%` is euclidean — it returns 0..6 even when the left side is
  // negative — so a Sunday under a Monday-first locale correctly walks six
  // days back rather than one forward.
  final back = (sundayIndex - firstDayOfWeekIndex) % 7;
  return addDays(startOfDay(day), -back);
}

/// Every local day in the half-open window `[from, to)`, in order.
List<DateTime> daysInWindow(DateTime from, DateTime to) {
  final days = <DateTime>[];
  for (var day = startOfDay(from); day.isBefore(to); day = addDays(day, 1)) {
    days.add(day);
  }
  return days;
}

/// How many calendar days the half-open window `[from, to)` spans.
///
/// Counted on UTC-normalised midnights so a window containing a
/// daylight-saving change is still a whole number of days — `to.difference`
/// would report 6 days and 23 hours for a week that lost an hour.
int windowLengthInDays(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// The reports screen's whole state: which window, which view, which filters.
///
/// Immutable, and every transition is a pure function returning a new one, so
/// the screen holds exactly one field and a `setState` can never leave half a
/// query applied.
class ReportQuery {
  const ReportQuery({
    required this.anchor,
    this.range = ReportRange.week,
    this.customFrom,
    this.customTo,
    this.view = ReportView.summary,
    this.clientIds = const <String>{},
    this.projectIds = const <String>{},
    this.taskIds = const <String>{},
    this.billableOnly = false,
  });

  /// The query the screen opens on: this week, everything, summary view.
  ReportQuery.at(DateTime now) : this(anchor: startOfDay(now));

  /// A day inside the window. Which window that is depends on [range]; the
  /// anchor itself is only ever a local midnight.
  final DateTime anchor;

  final ReportRange range;

  /// The custom window, used only when [range] is [ReportRange.custom].
  /// Half-open like every other window here: `[customFrom, customTo)`.
  final DateTime? customFrom;
  final DateTime? customTo;

  final ReportView view;

  /// The filter axes. An **empty** set means this axis filters nothing — it
  /// never means "match nothing". See `entriesInRange`.
  final Set<String> clientIds;
  final Set<String> projectIds;
  final Set<String> taskIds;

  final bool billableOnly;

  /// Whether anything is being filtered out — what the header's badge dot
  /// and the summary's footnote both key on.
  bool get hasFilters =>
      clientIds.isNotEmpty ||
      projectIds.isNotEmpty ||
      taskIds.isNotEmpty ||
      billableOnly;

  /// The half-open local window `[from, to)` this query resolves to.
  ///
  /// Half-open throughout: an entry starting at exactly midnight on the day
  /// the window ends belongs to the next window, never to both.
  (DateTime from, DateTime to) window(int firstDayOfWeekIndex) {
    switch (range) {
      case ReportRange.day:
        final from = startOfDay(anchor);
        return (from, addDays(from, 1));
      case ReportRange.week:
        final from = startOfWeek(anchor, firstDayOfWeekIndex);
        return (from, addDays(from, 7));
      case ReportRange.month:
        final from = startOfMonth(anchor);
        // Month 13 normalises to January of the next year, so December needs
        // no special case.
        return (from, DateTime(from.year, from.month + 1));
      case ReportRange.custom:
        final from = customFrom ?? startOfDay(anchor);
        return (from, customTo ?? addDays(from, 1));
    }
  }

  /// The same query moved [steps] windows forward (negative moves back).
  ///
  /// A month steps by *month*, not by 30 days, and lands on the first — so
  /// stepping forward from the 31st of January cannot overflow into March.
  /// A custom window steps by its own length, which is the only definition
  /// that makes the chevrons mean anything for an arbitrary range.
  ReportQuery shifted(int steps) {
    switch (range) {
      case ReportRange.day:
        return copyWith(anchor: addDays(anchor, steps));
      case ReportRange.week:
        return copyWith(anchor: addDays(anchor, 7 * steps));
      case ReportRange.month:
        return copyWith(anchor: DateTime(anchor.year, anchor.month + steps));
      case ReportRange.custom:
        final from = customFrom;
        final to = customTo;
        if (from == null || to == null) return this;
        final length = windowLengthInDays(from, to);
        if (length <= 0) return this;
        return withCustomWindow(
          addDays(from, length * steps),
          addDays(to, length * steps),
        );
    }
  }

  /// Whether the next window has started yet. Stepping into a window that
  /// begins in the future can only ever show an empty report, so the chevron
  /// that would do it is disabled instead.
  bool canAdvance(DateTime now, int firstDayOfWeekIndex) {
    final (from, _) = shifted(1).window(firstDayOfWeekIndex);
    return !from.isAfter(now.toLocal());
  }

  /// Switches which shape of window is in force, keeping the anchor — so
  /// Week → Month shows the month the visible week was in, rather than
  /// jumping somewhere the user was not looking.
  ReportQuery withRange(ReportRange next) => copyWith(range: next);

  /// Adopts an explicit window, which is what both the presets and the date
  /// picker on D4 produce.
  ReportQuery withCustomWindow(DateTime from, DateTime to) => ReportQuery(
    anchor: from,
    range: ReportRange.custom,
    customFrom: from,
    customTo: to,
    view: view,
    clientIds: clientIds,
    projectIds: projectIds,
    taskIds: taskIds,
    billableOnly: billableOnly,
  );

  /// Every filter axis off, the window untouched — the sheet's Clear button.
  ReportQuery withoutFilters() => copyWith(
    clientIds: const <String>{},
    projectIds: const <String>{},
    taskIds: const <String>{},
    billableOnly: false,
  );

  ReportQuery copyWith({
    DateTime? anchor,
    ReportRange? range,
    ReportView? view,
    Set<String>? clientIds,
    Set<String>? projectIds,
    Set<String>? taskIds,
    bool? billableOnly,
  }) => ReportQuery(
    anchor: anchor ?? this.anchor,
    range: range ?? this.range,
    // Carried, never cleared: switching to Week and back to Custom should
    // find the custom window still there. Use [withCustomWindow] to change it.
    customFrom: customFrom,
    customTo: customTo,
    view: view ?? this.view,
    clientIds: clientIds ?? this.clientIds,
    projectIds: projectIds ?? this.projectIds,
    taskIds: taskIds ?? this.taskIds,
    billableOnly: billableOnly ?? this.billableOnly,
  );
}
