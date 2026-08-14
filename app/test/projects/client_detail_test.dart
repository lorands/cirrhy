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
import 'package:cirrhy/projects/client_detail_screen.dart';
import 'package:cirrhy/settings/document_location_preference.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/theme/theme.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_document_directory.dart';

const _location = DocumentLocation(
  handle: 'memory:client-detail-test',
  label: 'Test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClientDetailScreen', () {
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
      // 1h this month, plus 2h last month — "this month" and "all time"
      // must read differently.
      await session.put(
        TimeEntry(
          id: 'e1',
          modified: now,
          start: DateTime.utc(2026, 8, 2, 9),
          stop: DateTime.utc(2026, 8, 2, 10),
          projectId: 'p1',
          taskId: 't1',
          locationChanged: now,
        ),
      );
      await session.put(
        TimeEntry(
          id: 'e2',
          modified: now,
          start: DateTime.utc(2026, 7, 2, 9),
          stop: DateTime.utc(2026, 7, 2, 11),
          projectId: 'p1',
          taskId: 't1',
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
          home: ClientDetailScreen(
            session: session,
            clientId: 'acme',
            clock: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'the stats card renders this-month and all-time totals separately',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        await seed(session);

        await pumpScreen(tester, session);

        expect(find.text('This month'), findsOneWidget);
        expect(find.text('All time'), findsOneWidget);
        expect(find.text('1:00'), findsOneWidget);
        expect(find.text('3:00'), findsOneWidget);
      },
    );

    testWidgets('renaming via the pencil icon persists the new name', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await seed(session);

      await pumpScreen(tester, session);
      await tester.tap(find.byKey(const Key('clientRenameButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('renameDialogField')),
        'Acme Industries',
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      await session.idle;
      await tester.pumpAndSettle();

      expect(session.document.clients['acme']!.name, 'Acme Industries');
      expect(find.text('Acme Industries'), findsWidgets);
    });

    testWidgets(
      'archiving pops back and the client is hidden from the projects list',
      (tester) async {
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
                      builder: (_) => ClientDetailScreen(
                        session: session,
                        clientId: 'acme',
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

        await tester.tap(find.text('Archive client'));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        expect(session.document.clients['acme']!.archived, isTrue);
        expect(find.byType(ClientDetailScreen), findsNothing);
      },
    );
  });
}
