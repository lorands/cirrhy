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
import 'package:cirrhy/projects/project_detail_screen.dart';
import 'package:cirrhy/settings/document_location_preference.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/theme/theme.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_document_directory.dart';

const _location = DocumentLocation(
  handle: 'memory:project-detail-test',
  label: 'Test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProjectDetailScreen', () {
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

    Future<void> seed(DocumentSession session) async {
      await session.put(Client(id: 'acme', modified: now, name: 'Acme Corp'));
      await session.put(Client(id: 'globex', modified: now, name: 'Globex'));
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
    }

    Future<void> pumpScreen(
      WidgetTester tester,
      DocumentSession session,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: cirrhyLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: ProjectDetailScreen(
            session: session,
            projectId: 'p1',
            clock: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a colour swatch persists it on the project', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await seed(session);

      await pumpScreen(tester, session);
      expect(session.document.projects['p1']!.color, '#3B82F6');

      await tester.tap(find.byKey(const Key('colorSwatch_#EC4899')));
      await tester.pump();
      await session.idle;
      await tester.pumpAndSettle();

      expect(session.document.projects['p1']!.color, '#EC4899');
    });

    testWidgets(
      'changing the client through the picker rebuilds the project with the '
      'new clientId and bumps locationChanged',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        await seed(session);
        final original = session.document.projects['p1']!;

        await pumpScreen(tester, session);
        expect(find.text('Acme Corp'), findsWidgets);

        now = now.add(const Duration(minutes: 10));
        await tester.tap(find.byKey(const Key('projectClientRow')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Globex'));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        final updated = session.document.projects['p1']!;
        expect(updated.clientId, 'globex');
        expect(updated.locationChanged, now);
        expect(updated.locationChanged, isNot(original.locationChanged));
      },
    );

    testWidgets(
      'choosing "No client" sets clientId to null and still relocates',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        await seed(session);

        await pumpScreen(tester, session);
        now = now.add(const Duration(minutes: 5));
        await tester.tap(find.byKey(const Key('projectClientRow')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('clientPickerNoClient')));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        final updated = session.document.projects['p1']!;
        expect(updated.clientId, isNull);
        expect(updated.locationChanged, now);
      },
    );

    testWidgets('the inline new-task field creates a task under this project', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await seed(session);

      await pumpScreen(tester, session);
      await tester.tap(find.text('New task…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('projectNewTaskField')),
        'Content migration',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await session.idle;
      await tester.pumpAndSettle();

      final created = session.document.tasks.values.firstWhere(
        (t) => t.name == 'Content migration',
      );
      expect(created.projectId, 'p1');
      expect(find.text('Content migration'), findsOneWidget);
    });

    testWidgets(
      'the run button on a task row starts a timer carrying its project and '
      'task',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        await seed(session);

        await pumpScreen(tester, session);
        await tester.tap(find.byTooltip('Start a new timer from this entry'));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        final timer = session.myTimer;
        expect(timer, isNotNull);
        expect(timer!.projectId, 'p1');
        expect(timer.taskId, 't1');
      },
    );

    testWidgets(
      'a task archived elsewhere (its own flag) vanishes from this list',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        await seed(session);

        await pumpScreen(tester, session);
        expect(find.text('Landing page'), findsOneWidget);

        await session.put(
          Task(
            id: 't1',
            modified: now,
            name: 'Landing page',
            projectId: 'p1',
            locationChanged: now,
            archived: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Landing page'), findsNothing);
      },
    );

    testWidgets('renaming the project via the pencil icon persists', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await seed(session);

      await pumpScreen(tester, session);
      await tester.tap(find.byKey(const Key('projectRenameButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('renameDialogField')),
        'Website relaunch',
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      await session.idle;
      await tester.pumpAndSettle();

      expect(session.document.projects['p1']!.name, 'Website relaunch');
    });

    testWidgets('archiving pops back and the project no longer resolves', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await seed(session);

      await tester.pumpWidget(
        MaterialApp(
          theme: cirrhyLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProjectDetailScreen(
                      session: session,
                      projectId: 'p1',
                      clock: () => now,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Archive project'));
      await tester.pump();
      await session.idle;
      await tester.pumpAndSettle();

      expect(session.document.projects['p1']!.archived, isTrue);
      expect(find.byType(ProjectDetailScreen), findsNothing);
    });
  });
}
