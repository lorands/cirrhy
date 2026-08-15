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
import 'package:cirrhy/l10n/duration_format.dart';
import 'package:cirrhy/l10n/generated/app_localizations.dart';
import 'package:cirrhy/settings/document_location_preference.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/theme/theme.dart';
import 'package:cirrhy/timer/entry_edit_screen.dart';
import 'package:cirrhy/timer/timer_screen.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_document_directory.dart';

const _location = DocumentLocation(handle: 'memory:timer-test', label: 'Test');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('formatDuration', () {
    test('minutes only, zero-padded', () {
      expect(formatDuration(const Duration(minutes: 45), 'en'), '0:45');
      expect(formatDuration(const Duration(minutes: 5), 'en'), '0:05');
    });

    test('hours are not zero-padded', () {
      expect(
        formatDuration(const Duration(hours: 6, minutes: 12), 'en'),
        '6:12',
      );
    });

    test('zero elapsed', () {
      expect(formatDuration(Duration.zero, 'en'), '0:00');
    });

    test('a negative duration clamps to zero rather than printing a sign', () {
      expect(formatDuration(const Duration(minutes: -5), 'en'), '0:00');
    });
  });

  group('formatTimer', () {
    test('every field is zero-padded, including the hour', () {
      expect(formatTimer(Duration.zero, 'en'), '00:00:00');
      expect(
        formatTimer(const Duration(hours: 1, minutes: 24, seconds: 36), 'en'),
        '01:24:36',
      );
    });

    test('a negative duration clamps to zero', () {
      expect(formatTimer(const Duration(seconds: -1), 'en'), '00:00:00');
    });
  });

  group('TimerScreen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    // The controllable clock every session in this file runs on. Matches the
    // pattern in document_session_test.dart: session time is always
    // `clock().toUtc()`, and the same function is handed to TimerScreen so
    // its ticking display reads the identical "now".
    var now = DateTime.utc(2026, 8, 13, 9);

    setUp(() => now = DateTime.utc(2026, 8, 13, 9));

    Future<DocumentSession> openSession(FakeDocumentDirectory directory) async {
      final preference = await DocumentLocationPreference.load();
      await preference.set(_location);
      final session = DocumentSession(
        directory: directory,
        locationPreference: preference,
        clock: () => now,
        deviceId: 'device-a',
      );
      await session.open();
      return session;
    }

    Future<void> pumpTimer(
      WidgetTester tester, {
      DocumentSession? session,
      Locale locale = const Locale('en'),
      // The test binding's default is android; EntryRow reads the platform
      // through the theme, so a desktop test just pins it here.
      TargetPlatform? platform,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: cirrhyLightTheme().copyWith(platform: platform),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: TimerScreen(session: session, clock: () => now),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the idle card renders, and Start begins a timer', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);

      await pumpTimer(tester, session: session);

      expect(find.text('What are you working on?'), findsOneWidget);
      expect(find.text('Select task'), findsOneWidget);
      expect(find.text('00:00:00'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Running'), findsNothing);

      await tester.tap(find.text('Start'));
      await tester.pump();
      await session.idle;
      await tester.pumpAndSettle();

      expect(session.myTimer, isNotNull);
      expect(find.text('Running'), findsOneWidget);
      expect(find.byKey(const Key('timerStopButton')), findsOneWidget);
    });

    testWidgets('the timer readout never wraps on a 360dp-wide phone', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 760); // Mate 10 Pro width.

      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await pumpTimer(tester, session: session);

      // A wrapped readout doubles the text's height; single-line 48px digits
      // stay around 50. The idle card broke first in the field — its Start
      // button leaves the digits the least room.
      final singleLine = lessThan(60.0);
      expect(tester.getSize(find.text('00:00:00')).height, singleLine);

      await tester.tap(find.text('Start'));
      await tester.pump();
      await session.idle;
      await tester.pumpAndSettle();

      expect(tester.getSize(find.text('00:00:00')).height, singleLine);
    });

    testWidgets('stopping the timer logs it as an entry in the list', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await session.startTimer(description: 'deep work');
      now = now.add(const Duration(minutes: 5));

      await pumpTimer(tester, session: session);
      // "deep work" is currently the running card's description.
      expect(find.text('deep work'), findsOneWidget);

      await tester.tap(find.byKey(const Key('timerStopButton')));
      await tester.pump();
      await session.idle;
      await tester.pumpAndSettle();

      expect(session.myTimer, isNull);
      expect(find.text('Running'), findsNothing);
      // Now it is the entry row's description instead, with its duration —
      // both the row's own figure and the day total, since it is the only
      // entry that day.
      expect(find.text('deep work'), findsOneWidget);
      expect(
        find.text(formatDuration(const Duration(minutes: 5), 'en')),
        findsNWidgets(2),
      );
    });

    testWidgets('the running display ticks forward every second, without '
        'accumulating drift', (tester) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await session.startTimer(description: 'ticking');

      await pumpTimer(tester, session: session);
      expect(find.text('00:00:00'), findsOneWidget);

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:00:01'), findsOneWidget);

      now = now.add(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('00:00:05'), findsOneWidget);
    });

    testWidgets('entries group by local day, with correct per-day totals', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);

      // Deliberately not "today" or "yesterday" relative to the test clock,
      // so the day header exercises the DateFormat.MMMEd fallback rather than
      // the special-cased labels.
      final dayA = DateTime.utc(2026, 8, 10, 9);
      final dayB = DateTime.utc(2026, 8, 9, 9);

      Future<void> log(String id, DateTime start, Duration length) =>
          session.put(
            TimeEntry(
              id: id,
              modified: start,
              start: start,
              stop: start.add(length),
              projectId: null,
              locationChanged: start,
              description: id,
            ),
          );

      await log('a1', dayA, const Duration(minutes: 20));
      await log(
        'a2',
        dayA.add(const Duration(hours: 2)),
        const Duration(minutes: 25),
      );
      await log('b1', dayB, const Duration(hours: 1));
      await log(
        'b2',
        dayB.add(const Duration(hours: 3)),
        const Duration(minutes: 40),
      );

      await pumpTimer(tester, session: session);

      expect(
        find.text(DateFormat.MMMEd('en').format(dayA.toLocal())),
        findsOneWidget,
      );
      expect(
        find.text(DateFormat.MMMEd('en').format(dayB.toLocal())),
        findsOneWidget,
      );
      // 20 + 25 minutes, 1h + 40 minutes — both totals distinct from any
      // single entry's own duration, so a match proves it is the group sum.
      expect(
        find.text(formatDuration(const Duration(minutes: 45), 'en')),
        findsOneWidget,
      );
      expect(
        find.text(formatDuration(const Duration(hours: 1, minutes: 40), 'en')),
        findsOneWidget,
      );
    });

    testWidgets('the run button on an entry restarts a timer with its '
        'project, task and description', (tester) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);

      await session.put(Client(id: 'acme', modified: now, name: 'Acme Corp'));
      await session.put(
        Project(
          id: 'p1',
          modified: now,
          name: 'Website',
          clientId: 'acme',
          locationChanged: now,
          color: '#3B82F6',
        ),
      );
      final past = TimeEntry(
        id: 'past',
        modified: now,
        start: now.subtract(const Duration(hours: 2)),
        stop: now.subtract(const Duration(hours: 1)),
        projectId: 'p1',
        locationChanged: now,
        taskId: null,
        description: 'design review',
      );
      await session.put(past);

      await pumpTimer(tester, session: session);
      expect(find.text('design review'), findsOneWidget);
      expect(find.text('Acme Corp › Website'), findsOneWidget);

      await tester.tap(find.byTooltip('Start a new timer from this entry'));
      await tester.pump();
      await session.idle;
      await tester.pumpAndSettle();

      final restarted = session.myTimer;
      expect(restarted, isNotNull);
      expect(restarted!.projectId, 'p1');
      expect(restarted.description, 'design review');
    });

    // The delete affordance follows the input idiom (entry_row.dart): a
    // per-row button on desktop platforms, swipe-left on touch ones. Both
    // funnel through the same confirmation dialog the entry editor uses.
    Future<DocumentSession> sessionWithPastEntry() async {
      final session = await openSession(FakeDocumentDirectory());
      await session.put(
        TimeEntry(
          id: 'past',
          modified: now,
          start: now.subtract(const Duration(hours: 2)),
          stop: now.subtract(const Duration(hours: 1)),
          projectId: null,
          locationChanged: now,
          taskId: null,
          description: 'design review',
        ),
      );
      return session;
    }

    testWidgets('desktop: each row carries a delete button that confirms, '
        'then deletes', (tester) async {
      final session = await sessionWithPastEntry();
      addTearDown(session.dispose);

      await pumpTimer(tester, session: session, platform: TargetPlatform.linux);
      expect(find.text('design review'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete entry'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this entry?'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pump();
      await session.idle;
      await tester.pumpAndSettle();

      expect(find.text('design review'), findsNothing);
      expect(session.document.entries.containsKey('past'), isFalse);
    });

    testWidgets('mobile: no per-row delete button; swiping left opens the '
        'confirmation, and cancelling keeps the entry', (tester) async {
      // The test default platform is android — exactly the touch case.
      final session = await sessionWithPastEntry();
      addTearDown(session.dispose);

      await pumpTimer(tester, session: session);
      expect(find.byTooltip('Delete entry'), findsNothing);

      await tester.drag(find.text('design review'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('Delete this entry?'), findsOneWidget);

      // Declining snaps the row back untouched.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('design review'), findsOneWidget);
      expect(session.document.entries.containsKey('past'), isTrue);

      await tester.drag(find.text('design review'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await session.idle;
      await tester.pumpAndSettle();

      expect(find.text('design review'), findsNothing);
      expect(session.document.entries.containsKey('past'), isFalse);
    });

    testWidgets('a null session renders an inert idle screen without '
        'crashing', (tester) async {
      await pumpTimer(tester, session: null);

      expect(find.text('What are you working on?'), findsOneWidget);
      expect(find.text('No entries yet'), findsOneWidget);

      final start = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(start.onPressed, isNull, reason: 'nothing to start into');

      // Tapping the disabled button is a no-op, not a crash.
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.text('Running'), findsNothing);
    });

    testWidgets('an entry with no description falls back to the '
        'placeholder', (tester) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await session.put(
        TimeEntry(
          id: 'blank',
          modified: now,
          start: now.subtract(const Duration(minutes: 10)),
          stop: now,
          projectId: null,
          locationChanged: now,
        ),
      );

      await pumpTimer(tester, session: session);

      expect(find.text('(no description)'), findsOneWidget);
    });

    testWidgets('an entry with no project omits the chip entirely', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await session.put(
        TimeEntry(
          id: 'no-project',
          modified: now,
          start: now.subtract(const Duration(minutes: 10)),
          stop: now,
          projectId: null,
          locationChanged: now,
          description: 'freelance thinking',
        ),
      );

      await pumpTimer(tester, session: session);

      expect(find.text('freelance thinking'), findsOneWidget);
      // No chip anywhere means no rendered text carries the "Client ›
      // Project" separator — a substring search proves the chip is absent
      // rather than merely that this exact combined string is absent.
      expect(find.textContaining('›'), findsNothing);
    });

    testWidgets('an open entry from another device shows the start and an '
        'ellipsis, with no duration, and does not crash', (tester) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await session.put(
        TimeEntry(
          id: 'still-open',
          modified: now,
          start: now.subtract(const Duration(minutes: 30)),
          stop: null,
          projectId: null,
          locationChanged: now,
          description: 'phone timer',
        ),
      );

      await pumpTimer(tester, session: session);

      final hm = DateFormat.Hm('en');
      expect(
        find.text(
          '${hm.format(now.subtract(const Duration(minutes: 30)).toLocal())} – …',
        ),
        findsOneWidget,
      );
    });

    testWidgets('day headers and clock times are formatted per locale', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);

      final day = DateTime.utc(2026, 8, 5, 14, 30);
      await session.put(
        TimeEntry(
          id: 'e1',
          modified: day,
          start: day,
          stop: day.add(const Duration(hours: 1)),
          projectId: null,
          locationChanged: day,
          description: 'work',
        ),
      );

      final dayLabels = <String, String>{};
      for (final locale in [const Locale('en'), const Locale('hu')]) {
        await pumpTimer(tester, session: session, locale: locale);

        final code = locale.languageCode;
        final dayLabel = DateFormat.MMMEd(code).format(day.toLocal());
        expect(find.text(dayLabel), findsOneWidget, reason: '$code day label');
        dayLabels[code] = dayLabel;

        final hm = DateFormat.Hm(code);
        final range =
            '${hm.format(day.toLocal())} – '
            '${hm.format(day.add(const Duration(hours: 1)).toLocal())}';
        expect(find.text(range), findsOneWidget, reason: '$code time range');
      }

      // Not just "some formatter ran" — the two locales must actually read
      // differently, or this test would pass even with the locale ignored.
      expect(dayLabels['en'], isNot(dayLabels['hu']));
    });

    testWidgets('the header + opens the entry screen in create mode, and '
        'saving there logs a new entry in the list', (tester) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);

      await pumpTimer(tester, session: session);
      await tester.tap(find.byKey(const Key('addEntryButton')));
      await tester.pumpAndSettle();

      expect(find.byType(EntryEditScreen), findsOneWidget);
      expect(find.text('Add entry'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'from memory');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await session.idle;
      await tester.pumpAndSettle();

      // Back on the timer list, with the manual entry logged under Today.
      expect(find.byType(EntryEditScreen), findsNothing);
      expect(session.document.entries.values.single.description, 'from memory');
      expect(find.text('from memory'), findsOneWidget);
    });

    testWidgets('backing out of create mode without saving writes nothing', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);

      await pumpTimer(tester, session: session);
      await tester.tap(find.byKey(const Key('addEntryButton')));
      await tester.pumpAndSettle();
      expect(find.byType(EntryEditScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(EntryEditScreen), findsNothing);
      expect(session.document.entries, isEmpty);
    });

    testWidgets('without a session the header + is inert', (tester) async {
      await pumpTimer(tester);
      await tester.tap(find.byKey(const Key('addEntryButton')));
      await tester.pumpAndSettle();
      expect(find.byType(EntryEditScreen), findsNothing);
    });
  });
}
