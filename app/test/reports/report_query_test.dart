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

import 'package:cirrhy/reports/report_query.dart';
import 'package:flutter_test/flutter_test.dart';

/// Monday = 1 in `MaterialLocalizations.firstDayOfWeekIndex`'s numbering,
/// which is what Hungarian (and most of Europe) resolves to; Sunday = 0 is
/// what en_US resolves to. Named here so the week tests read as the two real
/// cases rather than as two magic numbers.
const mondayFirst = 1;
const sundayFirst = 0;

void main() {
  // 13 August 2026 is a Thursday. Every expectation below is derived from
  // that one fact.
  final thursday = DateTime(2026, 8, 13, 9, 30);

  group('startOfWeek', () {
    test('a Monday-first locale walks back to Monday', () {
      expect(startOfWeek(thursday, mondayFirst), DateTime(2026, 8, 10));
    });

    test('a Sunday-first locale walks back to the day before', () {
      expect(startOfWeek(thursday, sundayFirst), DateTime(2026, 8, 9));
    });

    test('a Sunday under a Monday-first locale ends its own week, not starts '
        'one', () {
      // The case a naive `weekday - 1` gets wrong: Sunday is day seven, so it
      // walks six days back rather than one day forward.
      expect(
        startOfWeek(DateTime(2026, 8, 16, 23), mondayFirst),
        DateTime(2026, 8, 10),
      );
      expect(
        startOfWeek(DateTime(2026, 8, 16, 23), sundayFirst),
        DateTime(2026, 8, 16),
      );
    });

    test('a day already on the week start stays put', () {
      expect(
        startOfWeek(DateTime(2026, 8, 10, 18), mondayFirst),
        DateTime(2026, 8, 10),
      );
    });
  });

  group('window', () {
    test('a day window is exactly that local day, half-open', () {
      final query = ReportQuery(anchor: thursday, range: ReportRange.day);
      expect(query.window(mondayFirst), (
        DateTime(2026, 8, 13),
        DateTime(2026, 8, 14),
      ));
    });

    test('a week window is seven days from the locale week start', () {
      final query = ReportQuery(anchor: thursday);
      expect(query.window(mondayFirst), (
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 17),
      ));
      expect(query.window(sundayFirst), (
        DateTime(2026, 8, 9),
        DateTime(2026, 8, 16),
      ));
    });

    test('a month window runs first-to-first', () {
      final query = ReportQuery(anchor: thursday, range: ReportRange.month);
      expect(query.window(mondayFirst), (DateTime(2026, 8), DateTime(2026, 9)));
    });

    test('December rolls into January of the next year', () {
      final query = ReportQuery(
        anchor: DateTime(2026, 12, 24),
        range: ReportRange.month,
      );
      expect(query.window(mondayFirst), (DateTime(2026, 12), DateTime(2027)));
    });

    test('a custom window is returned as given', () {
      final query = ReportQuery(
        anchor: DateTime(2026, 8, 3),
      ).withCustomWindow(DateTime(2026, 8, 3), DateTime(2026, 8, 20));
      expect(query.window(mondayFirst), (
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 20),
      ));
    });
  });

  group('shifted', () {
    test('a day steps one day', () {
      final query = ReportQuery(anchor: thursday, range: ReportRange.day);
      expect(query.shifted(1).window(mondayFirst).$1, DateTime(2026, 8, 14));
      expect(query.shifted(-1).window(mondayFirst).$1, DateTime(2026, 8, 12));
    });

    test('a week steps seven days, staying on the same weekday', () {
      final query = ReportQuery(anchor: thursday);
      expect(query.shifted(-1).window(mondayFirst).$1, DateTime(2026, 8, 3));
      expect(query.shifted(2).window(mondayFirst).$1, DateTime(2026, 8, 24));
    });

    test('a month steps by month across the year boundary in both '
        'directions', () {
      final december = ReportQuery(
        anchor: DateTime(2026, 12, 24),
        range: ReportRange.month,
      );
      expect(december.shifted(1).window(mondayFirst), (
        DateTime(2027),
        DateTime(2027, 2),
      ));

      final january = ReportQuery(
        anchor: DateTime(2027, 1, 9),
        range: ReportRange.month,
      );
      expect(january.shifted(-1).window(mondayFirst), (
        DateTime(2026, 12),
        DateTime(2027),
      ));
    });

    test('a month step from a 31st cannot overflow into the month after '
        'next', () {
      // The bug this rules out: 31 January plus one month is 31 February,
      // which DateTime normalises to 3 March.
      final january = ReportQuery(
        anchor: DateTime(2027, 1, 31),
        range: ReportRange.month,
      );
      expect(january.shifted(1).window(mondayFirst), (
        DateTime(2027, 2),
        DateTime(2027, 3),
      ));
    });

    test('a custom window steps by its own length', () {
      // Ten days, 3–12 August inclusive.
      final query = ReportQuery(
        anchor: DateTime(2026, 8, 3),
      ).withCustomWindow(DateTime(2026, 8, 3), DateTime(2026, 8, 13));

      expect(query.shifted(1).window(mondayFirst), (
        DateTime(2026, 8, 13),
        DateTime(2026, 8, 23),
      ));
      expect(query.shifted(-1).window(mondayFirst), (
        DateTime(2026, 7, 24),
        DateTime(2026, 8, 3),
      ));
    });

    test('stepping a custom window forward and back returns to where it '
        'started', () {
      final query = ReportQuery(
        anchor: DateTime(2026, 8, 3),
      ).withCustomWindow(DateTime(2026, 8, 3), DateTime(2026, 8, 13));
      expect(
        query.shifted(1).shifted(-1).window(mondayFirst),
        query.window(mondayFirst),
      );
    });
  });

  group('canAdvance', () {
    test('the window containing now cannot advance', () {
      expect(
        ReportQuery.at(thursday).canAdvance(thursday, mondayFirst),
        isFalse,
      );
      expect(
        ReportQuery(
          anchor: thursday,
          range: ReportRange.day,
        ).canAdvance(thursday, mondayFirst),
        isFalse,
      );
      expect(
        ReportQuery(
          anchor: thursday,
          range: ReportRange.month,
        ).canAdvance(thursday, mondayFirst),
        isFalse,
      );
    });

    test('a past window can advance', () {
      expect(
        ReportQuery.at(thursday).shifted(-1).canAdvance(thursday, mondayFirst),
        isTrue,
      );
    });

    test('a custom window entirely in the past can advance until its next '
        'step would start in the future', () {
      final query = ReportQuery(
        anchor: DateTime(2026, 8, 1),
      ).withCustomWindow(DateTime(2026, 8, 1), DateTime(2026, 8, 11));
      expect(query.canAdvance(thursday, mondayFirst), isTrue);
      // The next step starts 21 August, which has not happened yet.
      expect(query.shifted(1).canAdvance(thursday, mondayFirst), isFalse);
    });
  });

  group('daysInWindow', () {
    test('enumerates every day of a week', () {
      final days = daysInWindow(DateTime(2026, 8, 10), DateTime(2026, 8, 17));
      expect(days.length, 7);
      expect(days.first, DateTime(2026, 8, 10));
      expect(days.last, DateTime(2026, 8, 16));
    });

    test('enumerates a 31-day month', () {
      expect(daysInWindow(DateTime(2026, 8), DateTime(2026, 9)).length, 31);
    });

    test('an empty window has no days', () {
      expect(
        daysInWindow(DateTime(2026, 8, 10), DateTime(2026, 8, 10)),
        isEmpty,
      );
    });
  });

  group('windowLengthInDays', () {
    test('counts calendar days, not elapsed hours', () {
      expect(
        windowLengthInDays(DateTime(2026, 8, 10), DateTime(2026, 8, 17)),
        7,
      );
      expect(windowLengthInDays(DateTime(2026, 8), DateTime(2026, 9)), 31);
    });
  });

  group('filters', () {
    test('an empty query is unfiltered', () {
      expect(ReportQuery.at(thursday).hasFilters, isFalse);
    });

    test('any axis makes it filtered, and clearing takes them all off', () {
      final filtered = ReportQuery.at(
        thursday,
      ).copyWith(projectIds: {'p1'}, billableOnly: true);
      expect(filtered.hasFilters, isTrue);
      expect(filtered.withoutFilters().hasFilters, isFalse);
      // Clearing filters is not a way to change the window.
      expect(
        filtered.withoutFilters().window(mondayFirst),
        filtered.window(mondayFirst),
      );
    });

    test('changing the range keeps the filters and the view', () {
      final query = ReportQuery.at(
        thursday,
      ).copyWith(clientIds: {'c1'}, view: ReportView.entries);
      final month = query.withRange(ReportRange.month);
      expect(month.clientIds, {'c1'});
      expect(month.view, ReportView.entries);
    });

    test('a custom window keeps the filters and the view', () {
      final query = ReportQuery.at(
        thursday,
      ).copyWith(taskIds: {'t1'}, view: ReportView.entries);
      final custom = query.withCustomWindow(
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 8),
      );
      expect(custom.taskIds, {'t1'});
      expect(custom.view, ReportView.entries);
      expect(custom.range, ReportRange.custom);
    });
  });
}
