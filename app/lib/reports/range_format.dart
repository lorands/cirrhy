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

/// Rendering a report window as text.
///
/// The companion to `l10n/duration_format.dart`, and held to the same rule
/// from CLAUDE.md: dates are the reporting feature's core output and every
/// one of them goes through an `intl` formatter. Nothing here builds a date
/// out of string pieces — "11 – 17 Aug 2026", "2026. aug. 11. – 17." and
/// "11.–17. Aug. 2026" differ by far more than the separator.
library;

import 'package:intl/intl.dart';

import 'report_query.dart';

/// The centred label between the two chevrons on the reports screen (D1).
///
/// [to] is exclusive, as every window in Cirrhy is, so the label names the
/// day *before* it — a week ending Monday-exclusive reads as ending Sunday.
///
/// A multi-day window is composed from two formatters rather than one
/// pattern: the start needs only its day number when both ends share a month,
/// which is what makes "11 – 17 Aug 2026" short enough to sit in a phone
/// header. When the window straddles a month or a year, both ends get the
/// full form instead — "28 – Sep 3" would otherwise silently drop August.
String formatReportRange(
  ReportRange range,
  DateTime from,
  DateTime to,
  String localeName,
) {
  final last = addDays(to, -1);

  if (range == ReportRange.month) {
    return DateFormat.yMMMM(localeName).format(from);
  }
  if (range == ReportRange.day || !last.isAfter(from)) {
    return DateFormat.yMMMEd(localeName).format(from);
  }

  final full = DateFormat.yMMMd(localeName);
  final sameMonth = from.year == last.year && from.month == last.month;
  final start = sameMonth
      ? DateFormat.d(localeName).format(from)
      : full.format(from);
  // An en dash with hair spacing either side, the range dash the design uses
  // throughout — not a hyphen, which reads as a minus next to numerals.
  return '$start – ${full.format(last)}';
}
