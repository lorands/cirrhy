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
import 'package:cirrhy/timer/entry_edit_screen.dart';
import 'package:cirrhy/timer/timer_screen.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_document_directory.dart';

const _location = DocumentLocation(
  handle: 'memory:entry-edit-test',
  label: 'Test',
);

const _unset = Object();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EntryEditScreen', () {
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

    TimeEntry entry({
      String id = 'e1',
      DateTime? start,
      // Sentinel rather than a plain default: callers need to be able to
      // pass `stop: null` explicitly (the still-open-entry case) and have
      // that stick, rather than falling back to a computed stop the way a
      // bare `stop ?? fallback` would.
      Object? stop = _unset,
      String? projectId,
      String? taskId,
      String description = 'deep work',
      DateTime? locationChanged,
      List<RecordVersion> history = const [],
    }) {
      final s = start ?? now.subtract(const Duration(hours: 2));
      final resolvedStop = identical(stop, _unset)
          ? s.add(const Duration(hours: 1))
          : stop as DateTime?;
      return TimeEntry(
        id: id,
        modified: s,
        start: s,
        stop: resolvedStop,
        projectId: projectId,
        locationChanged: locationChanged ?? s,
        taskId: taskId,
        description: description,
        history: history,
      );
    }

    Future<void> pumpEditor(
      WidgetTester tester,
      DocumentSession session,
      String entryId, {
      Locale locale = const Locale('en'),
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: cirrhyLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: EntryEditScreen(
            session: session,
            entryId: entryId,
            clock: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pumpTimerList(
      WidgetTester tester,
      DocumentSession session,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: cirrhyLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: TimerScreen(session: session, clock: () => now),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a row opens the editor prefilled', (tester) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await session.put(entry(description: 'design review'));

      await pumpTimerList(tester, session);
      expect(find.text('design review'), findsOneWidget);

      await tester.tap(find.text('design review'));
      await tester.pumpAndSettle();

      expect(find.byType(EntryEditScreen), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'design review');
    });

    testWidgets(
      'editing the description and saving updates the document, bumps '
      'modified, and leaves locationChanged untouched',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        final original = entry(
          description: 'old text',
          locationChanged: now.subtract(const Duration(days: 1)),
        );
        await session.put(original);

        await pumpEditor(tester, session, 'e1');
        await tester.enterText(find.byType(TextField), 'new text');

        now = now.add(const Duration(minutes: 5));
        await tester.tap(find.text('Save'));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        final saved = session.document.entries['e1']!;
        expect(saved.description, 'new text');
        expect(saved.modified, now);
        expect(saved.locationChanged, original.locationChanged);
        expect(find.byType(EntryEditScreen), findsNothing);
      },
    );

    testWidgets(
      'changing task via the picker updates taskId and projectId, and '
      'bumps locationChanged',
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
        final original = entry(
          projectId: null,
          taskId: null,
          locationChanged: now.subtract(const Duration(days: 1)),
        );
        await session.put(original);

        await pumpEditor(tester, session, 'e1');
        expect(find.text('Select task'), findsOneWidget);

        await tester.tap(find.text('Select task'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Landing page'));
        await tester.pumpAndSettle();

        expect(find.text('Acme › Website › Landing page'), findsOneWidget);

        now = now.add(const Duration(minutes: 1));
        await tester.tap(find.text('Save'));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        final saved = session.document.entries['e1']!;
        expect(saved.taskId, 't1');
        expect(saved.projectId, 'p1');
        expect(saved.locationChanged, now);
      },
    );

    testWidgets(
      'changing the date moves both start and stop, preserving clock times',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        final start = DateTime.utc(2026, 8, 10, 9, 15);
        final stop = DateTime.utc(2026, 8, 10, 10, 45);
        await session.put(entry(start: start, stop: stop));

        await pumpEditor(tester, session, 'e1');

        await tester.tap(find.byIcon(Icons.calendar_today));
        await tester.pumpAndSettle();
        // Move forward to the 15th of the same shown month.
        await tester.tap(find.text('15'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        final saved = session.document.entries['e1']!;
        expect(saved.start, DateTime.utc(2026, 8, 15, 9, 15));
        expect(saved.stop, DateTime.utc(2026, 8, 15, 10, 45));
      },
    );

    testWidgets(
      'a stop clock-time at or before start renders the next-day caption '
      'and saves an overnight duration',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        // Built from local wall-clock time rather than a fixed UTC instant:
        // whatever the host timezone, this is 22:00-23:00 as displayed.
        final startLocal = DateTime(2026, 8, 10, 22, 0);
        final stopLocal = DateTime(2026, 8, 10, 23, 0);
        await session.put(
          entry(start: startLocal.toUtc(), stop: stopLocal.toUtc()),
        );

        await pumpEditor(tester, session, 'e1');
        expect(
          find.text('Start and stop always travel together'),
          findsOneWidget,
        );

        // Open the stop time picker and set it to 01:00 — before start's
        // 22:00 clock time, which must roll to the next calendar day.
        await tester.tap(find.text(DateFormat.Hm('en').format(stopLocal)));
        await tester.pumpAndSettle();
        // Material's time picker opens on the dial by default; switch to
        // text entry for a deterministic set. The icon is the last one in
        // the dialog (after the "Select time" header's own icons).
        final dialogIcon =
            find
                    .descendant(
                      of: find.byType(Dialog),
                      matching: find.byType(Icon),
                    )
                    .evaluate()
                    .last
                    .widget
                as Icon;
        await tester.tap(find.byIcon(dialogIcon.icon!));
        await tester.pumpAndSettle();
        // Field 0 is this screen's own DESCRIPTION field, still in the tree
        // behind the dialog; 1 and 2 are the picker's hour and minute.
        await tester.enterText(find.byType(TextField).at(1), '01');
        await tester.enterText(find.byType(TextField).at(2), '00');
        await tester.tap(find.text('AM'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(find.text('Ends the next day'), findsOneWidget);

        await tester.tap(find.text('Save'));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        final expectedStop = DateTime(2026, 8, 11, 1, 0).toUtc();
        final saved = session.document.entries['e1']!;
        expect(saved.start, startLocal.toUtc());
        expect(saved.stop, expectedStop);
        expect(saved.stop!.difference(saved.start), const Duration(hours: 3));
      },
    );

    testWidgets(
      'delete, through the confirmation dialog, removes the entry and '
      'leaves a tombstone',
      (tester) async {
        final session = await openSession(FakeDocumentDirectory());
        addTearDown(session.dispose);
        await session.put(entry());

        await pumpEditor(tester, session, 'e1');
        await tester.tap(find.text('Delete entry'));
        await tester.pumpAndSettle();

        expect(find.text('Delete this entry?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(session.document.entries.containsKey('e1'), isTrue);

        await tester.tap(find.text('Delete entry'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        expect(session.document.entries.containsKey('e1'), isFalse);
        expect(session.document.tombstones.containsKey('e1'), isTrue);
      },
    );

    testWidgets(
      'after two edits the history section lists the demoted version, and '
      'Restore brings its description back in the document',
      (tester) async {
        // History only ever accrues from a genuine read-merge-write against
        // *something else's* change — DocumentRepository.save skips the
        // merge entirely when the file's hash still matches what this same
        // repository last wrote (see the "history through merge" group
        // below), so two sequential session.put calls with nothing else
        // touching the file in between would produce no history at all.
        // Simulating a second writer over the same store, exactly as another
        // device's sync would, is what makes this demotion real rather than
        // hand-waved.
        final directory = FakeDocumentDirectory();
        final session = await openSession(directory);
        addTearDown(session.dispose);
        await session.put(entry(description: 'first version'));

        now = now.add(const Duration(minutes: 10));
        final first = session.document.entries['e1']!;
        final other = DocumentRepository(store: directory.storeAt(_location));
        final theirs = await other.load();
        await other.save(
          theirs.put(
            TimeEntry(
              id: first.id,
              modified: now,
              start: first.start,
              stop: first.stop,
              projectId: first.projectId,
              locationChanged: first.locationChanged,
              taskId: first.taskId,
              description: 'second version',
              history: first.history,
            ),
          ),
        );
        await session.refresh();

        // The merge picked up on refresh demoted "first version" into
        // history.
        expect(session.document.entries['e1']!.description, 'second version');
        expect(session.document.entries['e1']!.history, hasLength(1));
        expect(
          session.document.entries['e1']!.history.single.fields['description'],
          'first version',
        );

        await pumpEditor(tester, session, 'e1');
        // The history card sits below the fold on the test surface; a plain
        // ListView only builds what the viewport (plus cache extent) covers,
        // so scrolling is required before it exists in the tree at all.
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(find.text('History'), findsOneWidget);
        expect(find.text('first version'), findsOneWidget);
        expect(find.text('Restore'), findsOneWidget);

        // Restore itself goes through the exact same session.put ->
        // read-merge-write path as Save — it has no special-cased history
        // handling of its own (per the screen's design: never hand-build a
        // history list in the UI layer). That path only ever demotes a
        // record when there is something to merge against, i.e. the file
        // changed since this repository's own last write; nothing has
        // touched it since session.refresh() above, so restoring here would
        // just overwrite "second version" outright rather than demote it.
        // A second external write reproduces the only situation in which
        // demotion actually happens — another writer having touched the
        // document in between — so Restore is tested under the same
        // condition Save already was.
        now = now.add(const Duration(minutes: 3));
        final again = DocumentRepository(store: directory.storeAt(_location));
        final theirsAgain = await again.load();
        await again.save(
          theirsAgain.put(
            Client(id: 'unrelated-2', modified: now, name: 'Unrelated 2'),
          ),
        );

        now = now.add(const Duration(minutes: 5));
        await tester.tap(find.text('Restore'));
        await tester.pump();
        await session.idle;
        await tester.pumpAndSettle();

        final restored = session.document.entries['e1']!;
        expect(restored.description, 'first version');
        expect(restored.history, isNotEmpty);
        expect(
          restored.history.any(
            (v) => v.fields['description'] == 'second version',
          ),
          isTrue,
          reason: 'the pre-restore live version must be demoted, not lost',
        );
      },
    );

    testWidgets('an open entry (stop null) renders with an inert stop field', (
      tester,
    ) async {
      final session = await openSession(FakeDocumentDirectory());
      addTearDown(session.dispose);
      await session.put(
        entry(
          start: now.subtract(const Duration(minutes: 30)),
          stop: null,
          description: 'still running',
        ),
      );

      await pumpEditor(tester, session, 'e1');

      expect(find.text('—'), findsWidgets);
      final hm = DateFormat.Hm('en');
      final label = hm.format(
        now.subtract(const Duration(minutes: 30)).toLocal(),
      );
      expect(find.text(label), findsOneWidget);

      // Tapping the em dash does nothing — no time picker opens.
      await tester.tap(find.text('—').first);
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsNothing);
    });
  });

  group('history through merge (non-widget)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a second put demotes the first version into history via the '
        "session's repository", () async {
      var now = DateTime.utc(2026, 8, 13, 9);
      final directory = FakeDocumentDirectory();
      final preference = await DocumentLocationPreference.load();
      await preference.set(_location);
      final session = DocumentSession(
        directory: directory,
        locationPreference: preference,
        clock: () => now,
        deviceId: 'device-a',
      );
      addTearDown(session.dispose);
      await session.open();

      final start = now.subtract(const Duration(hours: 1));
      final first = TimeEntry(
        id: 'e1',
        modified: now,
        start: start,
        stop: now,
        projectId: null,
        locationChanged: now,
        description: 'v1',
      );
      await session.put(first);
      expect(session.document.entries['e1']!.history, isEmpty);

      // DocumentRepository.save only merges — and so only demotes a loser
      // into history — when the file on disk no longer matches the hash
      // this repository last wrote. Two sequential `session.put` calls with
      // nothing else touching the store in between hit the fast path
      // instead (`stored.hash == _knownHash`) and just overwrite, with no
      // merge and so no history at all. An independent writer over the same
      // store — standing in for another device's sync — is what forces the
      // merge path this test is actually about.
      now = now.add(const Duration(minutes: 1));
      final other = DocumentRepository(store: directory.storeAt(_location));
      final theirs = await other.load();
      await other.save(
        theirs.put(Client(id: 'unrelated', modified: now, name: 'Unrelated')),
      );

      now = now.add(const Duration(minutes: 1));
      final second = TimeEntry(
        id: 'e1',
        modified: now,
        start: start,
        stop: now,
        projectId: null,
        locationChanged: first.locationChanged,
        description: 'v2',
        history: first.history,
      );
      await session.put(second);

      final saved = session.document.entries['e1']!;
      expect(saved.description, 'v2');
      expect(saved.history, hasLength(1));
      expect(saved.history.single.fields['description'], 'v1');
    });
  });
}
