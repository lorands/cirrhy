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
import 'package:cirrhy/timer/task_picker_sheet.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_document_directory.dart';

const _location = DocumentLocation(
  handle: 'memory:task-picker-test',
  label: 'Test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('task picker', () {
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

    // A minimal harness that opens the picker directly — the sheet's own
    // wiring from the timer screen is covered separately in
    // start_timer_sheet_test.dart, so this only needs a button and a
    // Navigator to push the sheet's route onto.
    TaskChoice? result;

    Future<void> pumpHarness(
      WidgetTester tester,
      DocumentSession session, {
      Locale locale = const Locale('en'),
    }) async {
      result = null;
      await tester.pumpWidget(
        MaterialApp(
          theme: cirrhyLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showTaskPicker(context, session);
                },
                child: const Text('open picker'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();
    }

    testWidgets('a task is findable by its client name, not just its own '
        'name', (tester) async {
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

      await pumpHarness(tester, session);
      expect(find.text('Landing page'), findsOneWidget);

      final search = find.byKey(const Key('taskPickerSearch'));
      await tester.enterText(search, 'Acme');
      await tester.pumpAndSettle();

      // Nothing in the query text matches the task's own name, only its
      // client's — proving the search really does reach up the hierarchy.
      expect(find.text('Landing page'), findsOneWidget);

      await tester.enterText(search, 'no such thing');
      await tester.pumpAndSettle();
      expect(find.text('Landing page'), findsNothing);
    });

    testWidgets(
      'the new-task flow creates the task in the document and returns it '
      'chosen',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        await pumpHarness(tester, session);

        // An empty document shows the placeholder…
        expect(
          find.text('Nothing here yet — create your first task below.'),
          findsOneWidget,
        );

        await tester.tap(find.text('New task…'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('taskPickerNewTaskField')),
          'Quarterly review',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        final createdId = result!.taskId;
        expect(result!.projectId, isNull);

        final created = session.document.tasks[createdId];
        expect(created, isNotNull);
        expect(created!.name, 'Quarterly review');
        expect(created.projectId, isNull);
      },
    );

    testWidgets(
      'the search field prefills the new-task field when it has text',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        await pumpHarness(tester, session);

        await tester.enterText(
          find.byKey(const Key('taskPickerSearch')),
          'Prefilled name',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('New task…'));
        await tester.pumpAndSettle();

        // The new-task field carries the search text across, unprompted —
        // checked on its controller directly, since the search field still
        // holds the identical string too.
        final field = tester.widget<TextField>(
          find.byKey(const Key('taskPickerNewTaskField')),
        );
        expect(field.controller!.text, 'Prefilled name');
      },
    );

    testWidgets('archived tasks and projects are excluded', (tester) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await session.put(Client(id: 'acme', modified: now, name: 'Acme Corp'));
      await session.put(
        Project(
          id: 'p1',
          modified: now,
          name: 'Live project',
          clientId: 'acme',
          locationChanged: now,
        ),
      );
      await session.put(
        Project(
          id: 'p2',
          modified: now,
          name: 'Dead project',
          clientId: 'acme',
          locationChanged: now,
          archived: true,
        ),
      );
      await session.put(
        Task(
          id: 't1',
          modified: now,
          name: 'Live task',
          projectId: 'p1',
          locationChanged: now,
        ),
      );
      await session.put(
        Task(
          id: 't2',
          modified: now,
          name: 'Dead task',
          projectId: 'p1',
          locationChanged: now,
          archived: true,
        ),
      );

      await pumpHarness(tester, session);

      expect(find.text('Live project'), findsOneWidget);
      expect(find.text('Live task'), findsOneWidget);
      expect(find.text('Dead project'), findsNothing);
      expect(find.text('Dead task'), findsNothing);
    });

    testWidgets(
      'a task under an archived client no longer appears in Recent, even '
      "though the task's own flag is untouched",
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        await session.put(Client(id: 'acme', modified: now, name: 'Acme'));
        await session.put(
          Project(
            id: 'p1',
            modified: now,
            name: 'Website',
            clientId: 'acme',
            locationChanged: now,
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
        // An entry puts the task in "Recent".
        await session.put(
          TimeEntry(
            id: 'e1',
            modified: now,
            start: now.subtract(const Duration(hours: 1)),
            stop: now,
            projectId: 'p1',
            taskId: 't1',
            locationChanged: now,
          ),
        );

        await pumpHarness(tester, session);
        // Once in "Recent" and once in the "All" hierarchy.
        expect(find.text('Landing page'), findsNWidgets(2));

        // Dismiss the sheet via its scrim before reopening it, rather than a
        // second full pumpHarness — pumping a brand-new MaterialApp on top of
        // an already-open modal route leaves its barrier intercepting the
        // next tap.
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();

        // Archive the client — never the task itself.
        await session.put(
          Client(id: 'acme', modified: now, name: 'Acme', archived: true),
        );
        expect(session.document.tasks['t1']!.archived, isFalse);

        await tester.tap(find.text('open picker'));
        await tester.pumpAndSettle();
        expect(find.text('Landing page'), findsNothing);
      },
    );

    testWidgets(
      'a project with no tasks yet is itself a valid, tappable choice',
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
          ),
        );
        // Deliberately no tasks under p1 — a client and a project created in
        // the Projects tab, but no task yet: the natural first-run path the
        // bug was filed against.

        await pumpHarness(tester, session);
        expect(find.text('Website'), findsOneWidget);

        await tester.tap(find.text('Website'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.projectId, 'p1');
        expect(result!.taskId, isNull);
      },
    );

    testWidgets('the sheet title renders in hu', (tester) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await pumpHarness(tester, session, locale: const Locale('hu'));

      expect(find.text('Feladat választása'), findsOneWidget);
    });
  });
}
