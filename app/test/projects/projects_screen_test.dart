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
import 'package:cirrhy/projects/projects_screen.dart';
import 'package:cirrhy/settings/document_location_preference.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/theme/theme.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_document_directory.dart';

const _location = DocumentLocation(
  handle: 'memory:projects-screen-test',
  label: 'Test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProjectsScreen', () {
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

    Future<void> pumpScreen(
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
          // ProjectsScreen is a tab body with no Scaffold of its own — in
          // the real app it is always hosted inside AppShell's Scaffold, so
          // the harness supplies one too, exactly as production does.
          home: Scaffold(
            body: ProjectsScreen(session: session, clock: () => now),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> seedTwoProjectClient(DocumentSession session) async {
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
        Project(
          id: 'p2',
          modified: now,
          name: 'Ops',
          clientId: 'acme',
          locationChanged: now,
          color: '#F59E0B',
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
      await session.put(
        Task(
          id: 't2',
          modified: now,
          name: 'Invoicing',
          projectId: 'p2',
          locationChanged: now,
        ),
      );
      // 1h under Website, 30m under Ops — both closed, both within August.
      await session.put(
        TimeEntry(
          id: 'e1',
          modified: now,
          start: DateTime.utc(2026, 8, 1, 9),
          stop: DateTime.utc(2026, 8, 1, 10),
          projectId: 'p1',
          taskId: 't1',
          locationChanged: now,
        ),
      );
      await session.put(
        TimeEntry(
          id: 'e2',
          modified: now,
          start: DateTime.utc(2026, 8, 1, 9),
          stop: DateTime.utc(2026, 8, 1, 9, 30),
          projectId: 'p2',
          taskId: 't2',
          locationChanged: now,
        ),
      );
    }

    testWidgets(
      'a client card renders the plural project count and this-month total, '
      'in en and in hu',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        await seedTwoProjectClient(session);

        await pumpScreen(tester, session);
        expect(find.text('Acme Corp'), findsOneWidget);
        expect(find.text('2 projects · 1:30 this month'), findsOneWidget);
        expect(find.text('1 task'), findsNWidgets(2));

        await pumpScreen(tester, session, locale: const Locale('hu'));
        expect(find.text('2 projekt · 1:30 ebben a hónapban'), findsOneWidget);
      },
    );

    testWidgets('the "No client" group totals only its own projects, not every '
        "client's", (tester) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      // A real client with an hour logged this month...
      await seedTwoProjectClient(session);
      // ...and a separate, unrelated no-client project with its own 20
      // minutes. The "No client" card must show only the latter.
      await session.put(
        Project(
          id: 'p3',
          modified: now,
          name: 'Freelance',
          clientId: null,
          locationChanged: now,
        ),
      );
      await session.put(
        TimeEntry(
          id: 'e3',
          modified: now,
          start: DateTime.utc(2026, 8, 1, 9),
          stop: DateTime.utc(2026, 8, 1, 9, 20),
          projectId: 'p3',
          locationChanged: now,
        ),
      );

      await pumpScreen(tester, session);
      expect(find.text('2 projects · 1:30 this month'), findsOneWidget);
      expect(find.text('1 project · 0:20 this month'), findsOneWidget);
    });

    testWidgets('the search field filters clients and projects by name', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await seedTwoProjectClient(session);
      await session.put(Client(id: 'globex', modified: now, name: 'Globex'));
      await session.put(
        Project(
          id: 'p3',
          modified: now,
          name: 'Rebrand',
          clientId: 'globex',
          locationChanged: now,
        ),
      );

      await pumpScreen(tester, session);
      expect(find.text('Acme Corp'), findsOneWidget);
      expect(find.text('Globex'), findsOneWidget);

      // Lowercase, so the search field's own echoed text ("globex") never
      // collides with the client card's capitalized display text.
      await tester.enterText(
        find.byKey(const Key('projectsSearchField')),
        'globex',
      );
      await tester.pumpAndSettle();

      expect(find.text('Globex'), findsOneWidget);
      expect(find.text('Acme Corp'), findsNothing);

      // A project-name match surfaces its client too.
      await tester.enterText(
        find.byKey(const Key('projectsSearchField')),
        'website',
      );
      await tester.pumpAndSettle();
      expect(find.text('Acme Corp'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
      // Ops does not match and Acme's own name doesn't either, so only the
      // matching project row is listed under it.
      expect(find.text('Ops'), findsNothing);
    });

    testWidgets(
      'an archived client is absent from the main list and appears under '
      'the expanded Archived section; Unarchive restores it',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        await session.put(Client(id: 'acme', modified: now, name: 'Acme Corp'));
        await session.put(
          Client(
            id: 'dead',
            modified: now,
            name: 'Dead Client',
            archived: true,
          ),
        );

        await pumpScreen(tester, session);
        expect(find.text('Acme Corp'), findsOneWidget);
        expect(find.text('Dead Client'), findsNothing);
        expect(find.text('Archived'), findsOneWidget);
        expect(find.text('1 item'), findsOneWidget);

        await tester.tap(find.byKey(const Key('archivedSectionToggle')));
        await tester.pumpAndSettle();
        expect(find.text('Dead Client'), findsOneWidget);
        expect(find.text('Unarchive'), findsOneWidget);

        await tester.tap(find.text('Unarchive'));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        expect(session.document.clients['dead']!.archived, isFalse);
        expect(find.text('Archived'), findsNothing);
        // Restored clients land in the main list, alphabetically ordered.
        expect(find.text('Dead Client'), findsOneWidget);
      },
    );

    testWidgets('an empty document shows the empty-state hint', (tester) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);

      await pumpScreen(tester, session);
      expect(
        find.text('No clients or projects yet — add one with +.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'tapping + opens the new-project sheet, and the created project '
      'appears on the list',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);

        await pumpScreen(tester, session);
        await tester.tap(find.byKey(const Key('newProjectHeaderButton')));
        await tester.pumpAndSettle();

        expect(find.text('New project'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('newProjectNameField')),
          'Freelance work',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('createProjectButton')));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('newProjectNameField')), findsNothing);
        expect(find.text('Freelance work'), findsOneWidget);
      },
    );
  });
}
