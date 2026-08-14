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

import 'package:cirrhy/data/document_session.dart';
import 'package:cirrhy/l10n/generated/app_localizations.dart';
import 'package:cirrhy/reports/custom_range_sheet.dart';
import 'package:cirrhy/reports/reports_screen.dart';
import 'package:cirrhy/settings/document_location_preference.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/theme/theme.dart';
import 'package:cirrhy/timer/entry_edit_screen.dart';
import 'package:cirrhy/widgets/entry_row.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_document_directory.dart';

const _location = DocumentLocation(handle: 'memory:reports-test', label: 'T');

/// Thursday, 13 August 2026. Everything the seed logs is placed relative to
/// it, and the two locales under test disagree about which week it is in —
/// Hungarian says Mon 10 – Sun 16, en_US says Sun 9 – Sat 15.
DateTime now = DateTime(2026, 8, 13, 9);

/// A local wall-clock instant in August 2026, stored as the UTC the records
/// actually carry. Building the seed from local times is what makes the day
/// bucketing deterministic wherever the suite runs.
DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 8, day, hour, minute).toUtc();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    now = DateTime(2026, 8, 13, 9);
    SharedPreferences.setMockInitialValues({});
  });

  Future<DocumentSession> openSession() async {
    final preference = await DocumentLocationPreference.load();
    await preference.set(_location);
    final session = DocumentSession(
      directory: FakeDocumentDirectory(),
      locationPreference: preference,
      clock: () => now,
      deviceId: 'device-a',
    );
    await session.open();
    return session;
  }

  /// The document every screen test reads.
  ///
  /// Two clients with one project each, so the client axis can only be
  /// satisfied through a project, and entries placed so that the en_US and
  /// Hungarian weeks, the month, and the previous week all differ.
  Future<DocumentSession> seeded() async {
    final session = await openSession();
    final stamp = now.toUtc();

    await session.put(Client(id: 'acme', modified: stamp, name: 'Acme'));
    await session.put(Client(id: 'cirrhy', modified: stamp, name: 'Cirrhy'));
    await session.put(
      Project(
        id: 'web',
        modified: stamp,
        name: 'Website',
        clientId: 'acme',
        locationChanged: stamp,
        color: '#3B82F6',
      ),
    );
    await session.put(
      Project(
        id: 'core',
        modified: stamp,
        name: 'Core',
        clientId: 'cirrhy',
        locationChanged: stamp,
        color: '#0E9F6E',
      ),
    );
    await session.put(
      Task(
        id: 'design',
        modified: stamp,
        name: 'Design',
        projectId: 'web',
        locationChanged: stamp,
      ),
    );

    Future<void> log(
      String id,
      DateTime start,
      DateTime stop, {
      String? projectId,
      String? taskId,
      bool billable = false,
    }) => session.put(
      TimeEntry(
        id: id,
        modified: start,
        start: start,
        stop: stop,
        projectId: projectId,
        taskId: taskId,
        billable: billable,
        locationChanged: start,
        description: id,
      ),
    );

    // Earlier in August, outside both readings of "this week".
    await log('early', at(3, 9), at(3, 11), projectId: 'core');
    // Sunday the 9th: inside the en_US week, outside the Hungarian one.
    await log('sunday', at(9, 9), at(9, 10), projectId: 'web');
    await log(
      'monday',
      at(10, 9),
      at(10, 12),
      projectId: 'web',
      taskId: 'design',
      billable: true,
    );
    await log('tuesday', at(11, 9), at(11, 11), projectId: 'core');
    await log('thursday', at(13, 8), at(13, 9), projectId: 'web');
    // Starts Thursday night and ends Friday morning: it belongs to Thursday.
    await log('midnight', at(13, 23, 30), at(14, 0, 30), projectId: 'web');
    // Still running, so it counts for nothing anywhere.
    await session.put(
      TimeEntry(
        id: 'open',
        modified: at(13, 10),
        start: at(13, 10),
        stop: null,
        projectId: 'web',
        locationChanged: at(13, 10),
        description: 'open',
      ),
    );
    // July, so only the previous month's window sees it.
    await session.put(
      TimeEntry(
        id: 'july',
        modified: DateTime(2026, 7, 20, 9).toUtc(),
        start: DateTime(2026, 7, 20, 9).toUtc(),
        stop: DateTime(2026, 7, 20, 10).toUtc(),
        projectId: 'core',
        locationChanged: DateTime(2026, 7, 20, 9).toUtc(),
        description: 'july',
      ),
    );

    return session;
  }

  Future<void> pumpReports(
    WidgetTester tester, {
    DocumentSession? session,
    Locale locale = const Locale('en'),
  }) async {
    // Tall enough that the whole report is laid out — a ListView does not
    // build what it cannot show, and half these assertions are below the fold
    // on a stock 800×600 test surface.
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: cirrhyLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: ReportsScreen(session: session, clock: () => now),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Finder chartBars() => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('chartBar-'),
  );

  group('summary (D1)', () {
    testWidgets('renders the range total, a bar per day and the per-project '
        'breakdown', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);

      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      // en_US weeks start on Sunday: Sun 9 (1h) + Mon 10 (3h) + Tue 11 (2h)
      // + Thu 13 (1h + the entry that runs past midnight, 1h) = 8h. The open
      // entry and the 3rd contribute nothing.
      expect(find.text('8:00'), findsOneWidget);

      expect(chartBars(), findsNWidgets(7));
      expect(find.text('By project'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
      expect(find.text('6:00'), findsOneWidget);
      expect(find.text('Core'), findsOneWidget);
      // Two hours on the Core project, and the same figure again above the
      // Tuesday and Thursday bars.
      expect(find.text('2:00'), findsNWidgets(3));

      // Nothing is filtered, so neither the badge nor the note is there.
      expect(find.byKey(const Key('reportsFilterBadge')), findsNothing);
      expect(find.textContaining('Filtered:'), findsNothing);
    });

    testWidgets('a bar is as tall as its day, and an empty day is a stub', (
      tester,
    ) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);

      double barHeight(String key) =>
          tester.getSize(find.byKey(Key(key))).height;

      // Monday is the longest day of the week, so it sets the scale.
      final monday = barHeight('chartBar-2026-8-10');
      final tuesday = barHeight('chartBar-2026-8-11');
      final wednesday = barHeight('chartBar-2026-8-12');

      expect(monday, greaterThan(tuesday));
      // 2h against a 3h tallest.
      expect(tuesday / monday, closeTo(2 / 3, 0.01));
      // Nothing was tracked on the Wednesday: a stub, not a bar.
      expect(wednesday, lessThan(6));
    });

    testWidgets('an entry that runs past midnight counts on the day it '
        'started', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);

      // Thursday holds an 08:00–09:00 entry plus one that starts at 23:30 and
      // ends after midnight. Friday must stay empty even so.
      final thursday = tester
          .getSize(find.byKey(const Key('chartBar-2026-8-13')))
          .height;
      final friday = tester
          .getSize(find.byKey(const Key('chartBar-2026-8-14')))
          .height;
      expect(thursday / friday, greaterThan(5));
      // Two hours against Monday's three.
      expect(find.text('2:00'), findsWidgets);
    });

    testWidgets('a range with nothing in it says so instead of drawing an '
        'empty chart', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      // Four weeks back is well before anything seeded.
      for (var i = 0; i < 4; i++) {
        await tapKey(tester, 'reportsPreviousRange');
      }

      expect(find.text('Nothing tracked in this range.'), findsOneWidget);
      expect(find.text('Total'), findsNothing);
      expect(chartBars(), findsNothing);
    });

    testWidgets('a null session renders an inert, empty tab', (tester) async {
      await pumpReports(tester);

      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('Nothing tracked in this range.'), findsOneWidget);
    });
  });

  group('range navigation', () {
    testWidgets('the day, month and week segments each resolve their own '
        'window', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      expect(find.text('8:00'), findsOneWidget);

      // Today alone: the 08:00 entry plus the one that starts at 23:30.
      await tapKey(tester, 'segment-ReportRange.day');
      expect(find.text('2:00'), findsWidgets);
      expect(chartBars(), findsOneWidget);

      // The whole of August, which adds the 3rd but not July.
      await tapKey(tester, 'segment-ReportRange.month');
      expect(find.text('10:00'), findsOneWidget);
      expect(chartBars(), findsNWidgets(31));

      await tapKey(tester, 'segment-ReportRange.week');
      expect(find.text('8:00'), findsOneWidget);
    });

    testWidgets('the next chevron is dead on the window containing today, and '
        'alive once you step back', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);

      IconButton next() =>
          tester.widget<IconButton>(find.byKey(const Key('reportsNextRange')));

      expect(next().onPressed, isNull);

      await tapKey(tester, 'reportsPreviousRange');
      expect(next().onPressed, isNotNull);
      // Sun 2 – Sat 8 holds only the two hours logged on the 3rd.
      expect(find.text('2:00'), findsWidgets);

      await tapKey(tester, 'reportsNextRange');
      expect(find.text('8:00'), findsOneWidget);
      expect(next().onPressed, isNull);
    });

    testWidgets('stepping a month back crosses into July', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      await tapKey(tester, 'segment-ReportRange.month');
      await tapKey(tester, 'reportsPreviousRange');

      expect(
        find.text(DateFormat.yMMMM('en').format(DateTime(2026, 7))),
        findsOneWidget,
      );
      expect(find.text('1:00'), findsWidgets);
    });
  });

  group('locale', () {
    testWidgets('the week starts where the locale starts it', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      // en_US: Sunday-first, so the Sunday entry is inside the week.
      await pumpReports(tester, session: session);
      expect(find.text('8:00'), findsOneWidget);

      // Hungarian: Monday-first, so the same Sunday belongs to the week
      // before and the total is an hour lighter.
      await pumpReports(tester, session: session, locale: const Locale('hu'));
      expect(find.text('7:00'), findsOneWidget);
    });

    testWidgets('the range label is formatted by the locale, not assembled '
        'by hand', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      // Sun 9 – Sat 15, composed from a day-only start and a full end.
      final english =
          '${DateFormat.d('en').format(DateTime(2026, 8, 9))} – '
          '${DateFormat.yMMMd('en').format(DateTime(2026, 8, 15))}';
      expect(find.text(english), findsOneWidget);

      await pumpReports(tester, session: session, locale: const Locale('hu'));
      final hungarian =
          '${DateFormat.d('hu').format(DateTime(2026, 8, 10))} – '
          '${DateFormat.yMMMd('hu').format(DateTime(2026, 8, 16))}';
      expect(find.text(hungarian), findsOneWidget);
      // Different week and different date order — the two must not collide.
      expect(hungarian, isNot(english));
    });

    testWidgets('every visible string comes from the Hungarian delegate', (
      tester,
    ) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session, locale: const Locale('hu'));

      expect(find.text('Jelentések'), findsOneWidget);
      expect(find.text('Összesen'), findsOneWidget);
      expect(find.text('Projektenként'), findsOneWidget);
      expect(find.text('Hét'), findsOneWidget);
    });
  });

  group('filters (D2)', () {
    Future<void> openFilters(WidgetTester tester) =>
        tapKey(tester, 'reportsFilterButton');

    testWidgets('the apply button counts what the draft filters keep, live', (
      tester,
    ) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      await openFilters(tester);

      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Show 5 entries'), findsOneWidget);

      // Acme owns Website: four of the five entries in the week.
      await tapKey(tester, 'clientFilter-acme');
      expect(find.text('Show 4 entries'), findsOneWidget);

      // Only one entry was marked billable, which also proves the ICU
      // singular branch renders.
      await tapKey(tester, 'clientFilter-acme');
      await tester.tap(find.byKey(const Key('billableOnlySwitch')));
      await tester.pumpAndSettle();
      expect(find.text('Show 1 entry'), findsOneWidget);
    });

    testWidgets('applying a filter narrows the report, raises the badge and '
        'names itself', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      await openFilters(tester);
      await tapKey(tester, 'clientFilter-acme');
      await tapKey(tester, 'applyFiltersButton');

      expect(find.text('6:00'), findsWidgets);
      expect(find.byKey(const Key('reportsFilterBadge')), findsOneWidget);
      expect(find.text('Filtered: Acme'), findsOneWidget);
      // Core belongs to the other client and is gone from the breakdown.
      expect(find.text('Core'), findsNothing);
    });

    testWidgets('the axes AND: a client and a project it does not own match '
        'nothing', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      await openFilters(tester);
      await tapKey(tester, 'clientFilter-acme');
      await tapKey(tester, 'projectFilter-core');

      // Selecting a client must not quietly widen the project axis.
      expect(find.text('Show 0 entries'), findsOneWidget);

      await tapKey(tester, 'applyFiltersButton');
      expect(find.text('Nothing tracked in this range.'), findsOneWidget);
    });

    testWidgets('Clear puts every axis back', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      await openFilters(tester);
      await tapKey(tester, 'clientFilter-acme');
      await tapKey(tester, 'taskFilter-design');
      await tester.tap(find.byKey(const Key('billableOnlySwitch')));
      await tester.pumpAndSettle();
      expect(find.text('Show 1 entry'), findsOneWidget);

      await tapKey(tester, 'clearFiltersButton');
      expect(find.text('Show 5 entries'), findsOneWidget);

      await tapKey(tester, 'applyFiltersButton');
      expect(find.byKey(const Key('reportsFilterBadge')), findsNothing);
    });

    testWidgets('dismissing the sheet changes nothing', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      await openFilters(tester);
      await tapKey(tester, 'clientFilter-acme');

      Navigator.of(tester.element(find.text('Filters'))).pop();
      await tester.pumpAndSettle();

      expect(find.text('8:00'), findsOneWidget);
      expect(find.byKey(const Key('reportsFilterBadge')), findsNothing);
    });

    testWidgets('an archived project is not offered as a filter', (
      tester,
    ) async {
      final session = await seeded();
      addTearDown(session.dispose);

      final core = session.document.projects['core']!;
      await session.put(
        Project(
          id: core.id,
          modified: now.toUtc(),
          name: core.name,
          clientId: core.clientId,
          locationChanged: core.locationChanged,
          color: core.color,
          archived: true,
        ),
      );

      await pumpReports(tester, session: session);
      await tapKey(tester, 'reportsFilterButton');

      expect(find.byKey(const Key('projectFilter-web')), findsOneWidget);
      expect(find.byKey(const Key('projectFilter-core')), findsNothing);
    });
  });

  group('entries view (D3)', () {
    Future<void> showEntries(WidgetTester tester) =>
        tapKey(tester, 'segment-ReportView.entries');

    testWidgets('lists the window\'s entries in day groups, with the shared '
        'row', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      await showEntries(tester);

      // The whole caption, not a fragment: "8:00" alone also matches the
      // 08:00–09:00 clock range inside one of the rows.
      final caption =
          '${DateFormat.d('en').format(DateTime(2026, 8, 9))} – '
          '${DateFormat.yMMMd('en').format(DateTime(2026, 8, 15))} '
          '· 5 entries · 8:00';
      expect(find.text(caption), findsOneWidget);
      expect(find.byType(EntryRow), findsNWidgets(5));

      // Thursday holds two of them; its header is the date, never "Today".
      expect(
        find.text(DateFormat.MMMEd('en').format(DateTime(2026, 8, 13))),
        findsOneWidget,
      );
      expect(find.text('Today'), findsNothing);

      expect(
        find.text('Every row keeps its run button — reports restart work too.'),
        findsOneWidget,
      );
    });

    testWidgets('the view segment swaps the body and keeps the window', (
      tester,
    ) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      await tapKey(tester, 'reportsPreviousRange');
      await showEntries(tester);

      // The previous week has exactly one entry in it.
      expect(find.textContaining('1 entry'), findsOneWidget);
      expect(find.byType(EntryRow), findsOneWidget);
      expect(chartBars(), findsNothing);

      await tapKey(tester, 'segment-ReportView.summary');
      expect(chartBars(), findsNWidgets(7));
      expect(find.byType(EntryRow), findsNothing);
    });

    testWidgets('a row\'s run button restarts that entry', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      await showEntries(tester);
      expect(session.myTimer, isNull);

      // Newest first, so the first row is the entry that ran past midnight.
      await tester.tap(find.byType(RunButton).first);
      await tester.pump();
      await session.idle;
      await tester.pumpAndSettle();

      expect(session.myTimer, isNotNull);
      expect(session.myTimer!.projectId, 'web');
      expect(session.myTimer!.description, 'midnight');
    });

    testWidgets('tapping a row opens the entry editor', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      await showEntries(tester);

      await tester.tap(find.text('thursday'));
      await tester.pumpAndSettle();

      expect(find.byType(EntryEditScreen), findsOneWidget);
    });
  });

  group('custom range (D4)', () {
    testWidgets('the Custom segment opens the sheet, and dismissing it leaves '
        'the range alone', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      await tapKey(tester, 'segment-ReportRange.custom');

      expect(find.text('Custom range'), findsOneWidget);
      Navigator.of(tester.element(find.text('Custom range'))).pop();
      await tester.pumpAndSettle();

      expect(find.text('8:00'), findsOneWidget);
    });

    testWidgets('each preset resolves the window it names', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      Future<void> preset(String name) async {
        await tapKey(tester, 'segment-ReportRange.custom');
        await tapKey(tester, 'preset-$name');
      }

      await pumpReports(tester, session: session);

      await preset('thisWeek');
      expect(find.text('8:00'), findsOneWidget);

      // Sun 2 – Sat 8, holding only the two hours on the 3rd.
      await preset('lastWeek');
      expect(find.text('2:00'), findsWidgets);

      await preset('thisMonth');
      expect(find.text('10:00'), findsOneWidget);

      // 15 July – 13 August inclusive: everything except nothing, since the
      // July entry falls inside it too.
      await preset('last30');
      expect(find.text('11:00'), findsOneWidget);
    });

    testWidgets('a preset window then steps by its own length', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      await tapKey(tester, 'segment-ReportRange.custom');
      await tapKey(tester, 'preset-thisWeek');
      expect(find.text('8:00'), findsOneWidget);

      // Seven days back from a seven-day window.
      await tapKey(tester, 'reportsPreviousRange');
      expect(find.text('2:00'), findsWidgets);
    });

    testWidgets('the presets follow the locale\'s week start', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session, locale: const Locale('hu'));
      await tapKey(tester, 'segment-ReportRange.custom');
      await tapKey(tester, 'preset-thisWeek');

      // Monday-first, so the Sunday entry is not in it.
      expect(find.text('7:00'), findsOneWidget);
    });

    testWidgets('the Pick dates row opens the platform date range picker, and '
        'cancelling it leaves the range alone', (tester) async {
      final session = await seeded();
      addTearDown(session.dispose);

      await pumpReports(tester, session: session);
      await tapKey(tester, 'segment-ReportRange.custom');
      await tapKey(tester, 'pickDatesRow');

      // Material's own picker, deliberately, rather than a calendar of our
      // own — see the note on showCustomRangeSheet.
      expect(find.byType(DateRangePickerDialog), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('8:00'), findsOneWidget);
    });

    test('presetWindow is arithmetic, not a widget', () {
      // The four windows, checked directly against a Monday-first locale.
      expect(presetWindow(RangePreset.thisWeek, now, 1), (
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 17),
      ));
      expect(presetWindow(RangePreset.lastWeek, now, 1), (
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 10),
      ));
      expect(presetWindow(RangePreset.thisMonth, now, 1), (
        DateTime(2026, 8),
        DateTime(2026, 9),
      ));
      expect(presetWindow(RangePreset.last30, now, 1), (
        DateTime(2026, 7, 15),
        DateTime(2026, 8, 14),
      ));
    });
  });
}
