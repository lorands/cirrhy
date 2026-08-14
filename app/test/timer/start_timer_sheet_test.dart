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
import 'package:cirrhy/settings/document_location_preference.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/theme/theme.dart';
import 'package:cirrhy/timer/timer_screen.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_document_directory.dart';

const _location = DocumentLocation(
  handle: 'memory:start-timer-test',
  label: 'Test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('start-timer sheet', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

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
      WidgetTester tester,
      DocumentSession session, {
      Locale locale = const Locale('en'),
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: cirrhyLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: Scaffold(body: TimerScreen(session: session)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tapping the idle-card hint opens the sheet', (tester) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await pumpTimer(tester, session);

      expect(find.text('Start timer'), findsNothing);
      await tester.tap(find.text('What are you working on?'));
      await tester.pumpAndSettle();
      expect(find.text('Start timer'), findsOneWidget);
    });

    testWidgets('tapping the idle-card chip also opens the sheet', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await pumpTimer(tester, session);

      await tester.tap(find.text('Select task'));
      await tester.pumpAndSettle();
      expect(find.text('Start timer'), findsOneWidget);
    });

    testWidgets(
      'typing a description and pressing Start starts a timer with that '
      'description',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        await pumpTimer(tester, session);

        await tester.tap(find.text('What are you working on?'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('startTimerSheetDescription')),
          'writing tests',
        );
        await tester.tap(find.byKey(const Key('startTimerSheetStart')));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        expect(session.myTimer, isNotNull);
        expect(session.myTimer!.description, 'writing tests');
        // The sheet closed itself after starting.
        expect(find.text('Start timer'), findsNothing);
      },
    );

    testWidgets(
      'choosing a task through the picker fills the selector chip and the '
      'started timer carries taskId and projectId',
      (tester) async {
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
        await session.put(
          Task(
            id: 't1',
            modified: now,
            name: 'Landing page',
            projectId: 'p1',
            locationChanged: now,
          ),
        );

        await pumpTimer(tester, session);
        await tester.tap(find.text('What are you working on?'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('startTimerSheetTaskSelector')));
        await tester.pumpAndSettle();
        expect(find.text('Choose task'), findsOneWidget);

        await tester.tap(find.text('Landing page'));
        await tester.pumpAndSettle();

        // Back on the start-timer sheet, the selector now shows the full path.
        expect(find.text('Acme Corp › Website › Landing page'), findsOneWidget);

        await tester.tap(find.byKey(const Key('startTimerSheetStart')));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        final started = session.myTimer;
        expect(started, isNotNull);
        expect(started!.taskId, 't1');
        expect(started.projectId, 'p1');
      },
    );

    testWidgets(
      'recent chips appear from entries and tapping one starts the matching '
      'timer',
      (tester) async {
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
        await session.put(
          TimeEntry(
            id: 'e1',
            modified: now,
            start: now.subtract(const Duration(hours: 2)),
            stop: now.subtract(const Duration(hours: 1)),
            projectId: 'p1',
            locationChanged: now,
            description: 'design review',
          ),
        );

        await pumpTimer(tester, session);
        await tester.tap(find.text('What are you working on?'));
        await tester.pumpAndSettle();

        // The background entry list, still mounted under the sheet, shows
        // the same "design review" text for the logged entry itself — so
        // the recent-chips row (the only Wrap on screen) is what scopes this
        // to the chip rather than that entry row.
        final recentChip = find.descendant(
          of: find.byType(Wrap),
          matching: find.text('design review'),
        );
        expect(find.text('Recent'), findsOneWidget);
        expect(recentChip, findsOneWidget);

        await tester.tap(recentChip);
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        final started = session.myTimer;
        expect(started, isNotNull);
        expect(started!.projectId, 'p1');
        expect(started.description, 'design review');
        expect(find.text('Start timer'), findsNothing);
      },
    );

    testWidgets('the sheet title renders in hu', (tester) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await pumpTimer(tester, session, locale: const Locale('hu'));

      await tester.tap(find.text('Min dolgozol?'));
      await tester.pumpAndSettle();

      expect(find.text('Időmérő indítása'), findsOneWidget);
    });
  });
}
