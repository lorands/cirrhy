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

import 'dart:io';

import 'package:cirrhy/data/document_session.dart';
import 'package:cirrhy/data/session_refresher.dart';
import 'package:cirrhy/l10n/generated/app_localizations.dart';
import 'package:cirrhy/settings/document_location_preference.dart';
import 'package:cirrhy/shell/app_shell.dart';
import 'package:cirrhy/storage/document_directory.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/storage/path_document_directory.dart';
import 'package:cirrhy/theme/theme.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_document_directory.dart';

/// The session against real folders, per the relocation_test pattern: the
/// promises here — merged relocation, refresh-on-resume, surviving a blocked
/// save — are exactly the ones DESIGN.md §3–§4 makes about files on disk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = JsonDocumentCodec();

  late Directory dirA;
  late Directory dirB;

  /// The controllable clock. Session time is always `clock().toUtc()`.
  var now = DateTime.utc(2026, 8, 13, 9);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 8, 13, 9);
    dirA = Directory.systemTemp.createTempSync('cirrhy_session_a');
    dirB = Directory.systemTemp.createTempSync('cirrhy_session_b');
  });

  tearDown(() {
    for (final dir in [dirA, dirB]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  DocumentLocation locate(Directory dir) =>
      DocumentLocation(handle: dir.path, label: dir.path);

  File fileIn(Directory dir) => File(p.join(dir.path, documentFileName));

  CirrhyDocument onDisk(Directory dir) =>
      codec.decode(fileIn(dir).readAsBytesSync());

  TimeEntry entry(String id, {int minute = 0}) => TimeEntry(
    id: id,
    modified: DateTime.utc(2026, 8, 13, 8, minute),
    start: DateTime.utc(2026, 8, 13, 8, minute),
    stop: DateTime.utc(2026, 8, 13, 8, minute + 30),
    projectId: null,
    locationChanged: DateTime.utc(2026, 8, 13, 8, minute),
    description: id,
  );

  /// A session already open on [dir], with the location preference pointing
  /// there. The preference is set *before* construction so setup does not
  /// exercise the location listener the relocation tests target.
  Future<(DocumentSession, DocumentLocationPreference)> openAt(
    Directory dir, {
    String deviceId = 'device-a',
  }) async {
    final preference = await DocumentLocationPreference.load();
    await preference.set(locate(dir));
    final session = DocumentSession(
      directory: const PathDocumentDirectory(),
      locationPreference: preference,
      clock: () => now,
      deviceId: deviceId,
    );
    addTearDown(session.dispose);
    await session.open();
    return (session, preference);
  }

  group('lifecycle', () {
    test('opening an empty folder is ready with an empty document', () async {
      final (session, _) = await openAt(dirA);

      expect(session.status, SessionStatus.ready);
      expect(session.document.recordCount, 0);
      expect(session.myTimer, isNull);
      expect(session.lastError, isNull);
    });

    test('opening an unreachable folder degrades to unavailable', () async {
      dirA.deleteSync(recursive: true);

      final (session, _) = await openAt(dirA);

      expect(session.status, SessionStatus.unavailable);
      expect(session.lastError, isA<DocumentLocationUnavailable>());
      expect(session.document.recordCount, 0);
    });
  });

  group('timer', () {
    test('start and stop round-trip into one time entry', () async {
      final (session, _) = await openAt(dirA);
      final startedAt = now;

      await session.startTimer(description: 'deep work');
      expect(session.myTimer, isNotNull);
      expect(session.myTimer!.startedAt, startedAt);

      now = now.add(const Duration(minutes: 25));
      await session.stopTimer();

      expect(session.myTimer, isNull);
      final logged = session.document.entries.values.single;
      expect(logged.start, startedAt);
      expect(logged.stop, now);
      expect(logged.description, 'deep work');

      // And the same is true of the file, not just of memory.
      final stored = onDisk(dirA);
      expect(stored.runningTimers, isEmpty);
      expect(stored.entries.values.single.start, startedAt);
      expect(stored.entries.values.single.stop, now);
    });

    test(
      'starting while running closes the old interval, in one save',
      () async {
        final (session, _) = await openAt(dirA);
        final firstStart = now;
        await session.startTimer(description: 'first');

        var notifications = 0;
        session.addListener(() => notifications++);

        now = now.add(const Duration(minutes: 10));
        await session.startTimer(description: 'second');

        // One commit: the stop and the new start were a single save, so no
        // window exists where the first interval was neither running nor
        // logged.
        expect(notifications, 1);

        final logged = session.document.entries.values.single;
        expect(logged.start, firstStart);
        expect(logged.stop, now);
        expect(logged.description, 'first');
        expect(session.myTimer!.startedAt, now);
        expect(session.myTimer!.description, 'second');

        final stored = onDisk(dirA);
        expect(stored.entries.values.single.description, 'first');
        expect(stored.runningTimers.values.single.description, 'second');
      },
    );

    test('restartFrom copies project, task and description', () async {
      final (session, _) = await openAt(dirA);
      final past = TimeEntry(
        id: 'past',
        modified: now,
        start: now.subtract(const Duration(hours: 2)),
        stop: now.subtract(const Duration(hours: 1)),
        projectId: 'project-1',
        locationChanged: now,
        taskId: 'task-1',
        description: 'the usual',
      );
      await session.put(past);

      now = now.add(const Duration(minutes: 5));
      await session.restartFrom(past);

      final timer = session.myTimer!;
      expect(timer.projectId, 'project-1');
      expect(timer.taskId, 'task-1');
      expect(timer.description, 'the usual');
      expect(timer.startedAt, now);
    });

    test('updateTimer changes task, project and description but keeps '
        'startedAt untouched, and persists', () async {
      final (session, _) = await openAt(dirA);
      final startedAt = now;
      await session.startTimer(description: 'first draft');

      now = now.add(const Duration(minutes: 10));
      await session.updateTimer(
        projectId: 'project-1',
        taskId: 'task-1',
        description: 'final draft',
      );

      final timer = session.myTimer!;
      expect(timer.startedAt, startedAt);
      expect(timer.modified, now);
      expect(timer.projectId, 'project-1');
      expect(timer.taskId, 'task-1');
      expect(timer.description, 'final draft');

      // Not just in memory — the same is true of the file.
      final stored = onDisk(dirA).runningTimers.values.single;
      expect(stored.startedAt, startedAt);
      expect(stored.projectId, 'project-1');
      expect(stored.taskId, 'task-1');
      expect(stored.description, 'final draft');
    });

    test('a later stopTimer files an entry carrying the updated fields but the '
        'original start', () async {
      final (session, _) = await openAt(dirA);
      final startedAt = now;
      await session.startTimer(description: 'first draft');

      now = now.add(const Duration(minutes: 10));
      await session.updateTimer(
        projectId: 'project-1',
        taskId: 'task-1',
        description: 'final draft',
      );

      now = now.add(const Duration(minutes: 20));
      await session.stopTimer();

      expect(session.myTimer, isNull);
      final logged = session.document.entries.values.single;
      expect(logged.start, startedAt);
      expect(logged.stop, now);
      expect(logged.projectId, 'project-1');
      expect(logged.taskId, 'task-1');
      expect(logged.description, 'final draft');
    });

    test(
      'updateTimer is a no-op when this device has no running timer',
      () async {
        final (session, _) = await openAt(dirA);

        await session.updateTimer(description: 'nothing to edit into');

        expect(session.myTimer, isNull);
        expect(session.document.runningTimers, isEmpty);
      },
    );
  });

  group('records', () {
    test('delete leaves a tombstone rather than just removing', () async {
      final (session, _) = await openAt(dirA);
      final client = Client(id: 'acme', modified: now, name: 'Acme');
      await session.put(client);
      expect(session.clientById('acme'), isNotNull);

      now = now.add(const Duration(minutes: 1));
      await session.delete('acme');

      expect(session.clientById('acme'), isNull);
      expect(session.document.tombstones['acme']!.deletedAt, now);
      // On disk too — a peer's merge must see the deletion, not an absence.
      expect(onDisk(dirA).tombstones.containsKey('acme'), isTrue);
    });
  });

  group('relocation', () {
    test('moving into an occupied folder merges and leaves the old '
        'file', () async {
      final (session, preference) = await openAt(dirA);
      await session.put(entry('laptop-work'));

      // The target folder already holds another device's history.
      final other = DocumentRepository(store: PathDocumentStore(locate(dirB)));
      await other.load();
      await other.save(
        const CirrhyDocument.empty().put(entry('phone-work', minute: 30)),
      );

      await preference.set(locate(dirB));
      await session.idle;

      expect(session.status, SessionStatus.ready);
      expect(
        session.document.entries.keys,
        unorderedEquals(['laptop-work', 'phone-work']),
      );
      expect(
        onDisk(dirB).entries.keys,
        unorderedEquals(['laptop-work', 'phone-work']),
      );
      // §4.6: the old file is not ours to delete.
      expect(fileIn(dirA).existsSync(), isTrue);
      expect(onDisk(dirA).entries.keys, ['laptop-work']);
    });

    test('a location chosen at first run opens the session', () async {
      // First run: no location yet, so the session idles.
      final preference = await DocumentLocationPreference.load();
      final session = DocumentSession(
        directory: const PathDocumentDirectory(),
        locationPreference: preference,
        clock: () => now,
        deviceId: 'device-a',
      );
      addTearDown(session.dispose);
      await session.open();
      expect(session.status, SessionStatus.idle);

      // The picker lands on a folder; the session follows the preference.
      await preference.set(locate(dirA));
      await session.idle;

      expect(session.status, SessionStatus.ready);
    });
  });

  group('refresh', () {
    test('picks up an external write and reports the delta', () async {
      final (session, _) = await openAt(dirA);
      await session.put(entry('mine'));

      // A sync client delivers another device's save into the same folder.
      final other = DocumentRepository(store: PathDocumentStore(locate(dirA)));
      final theirs = await other.load();
      await other.save(theirs.put(entry('theirs', minute: 30)));

      now = now.add(const Duration(minutes: 3));
      await session.refresh();

      expect(
        session.document.entries.keys,
        unorderedEquals(['mine', 'theirs']),
      );
      expect(session.lastRefreshNewRecords, 1);
      expect(session.lastRefreshed, now);

      // Nothing new the second time.
      await session.refresh();
      expect(session.lastRefreshNewRecords, 0);
    });

    test('an unreachable folder goes unavailable without losing '
        'memory', () async {
      final (session, _) = await openAt(dirA);
      await session.startTimer(description: 'tracked');

      dirA.deleteSync(recursive: true);
      await session.refresh();

      expect(session.status, SessionStatus.unavailable);
      expect(session.lastError, isA<DocumentLocationUnavailable>());
      expect(session.myTimer, isNotNull, reason: 'memory must survive');

      // Mutations keep working in memory while the folder is gone.
      now = now.add(const Duration(minutes: 5));
      await session.stopTimer();
      expect(session.myTimer, isNull);
      expect(session.document.entries.values.single.description, 'tracked');
      expect(session.status, SessionStatus.unavailable);

      // The folder comes back (a remounted share): the next commit persists
      // everything that happened while it was gone.
      dirA.createSync(recursive: true);
      await session.put(Client(id: 'acme', modified: now, name: 'Acme'));

      expect(session.status, SessionStatus.ready);
      final stored = onDisk(dirA);
      expect(stored.entries.values.single.description, 'tracked');
      expect(stored.clients.keys, ['acme']);
    });
  });

  group('foreign timers', () {
    /// Another device's save landing in the same folder — the situation §3.6
    /// exists for.
    Future<void> writeExternal(
      Directory dir,
      CirrhyDocument Function(CirrhyDocument doc) change,
    ) async {
      final other = DocumentRepository(store: PathDocumentStore(locate(dir)));
      final theirs = await other.load();
      await other.save(change(theirs));
    }

    RunningTimer foreignTimer(
      String deviceId,
      DateTime startedAt, {
      String description = '',
    }) => RunningTimer(
      deviceId: deviceId,
      modified: startedAt,
      startedAt: startedAt,
      description: description,
    );

    test('stopForeignTimer files the interval as an entry, on disk '
        'too', () async {
      final (session, _) = await openAt(dirA);
      final startedAt = DateTime.utc(2026, 8, 13, 8, 13);
      await writeExternal(
        dirA,
        (doc) => doc.put(foreignTimer('phone', startedAt, description: 'call')),
      );
      await session.refresh();
      expect(session.foreignTimers.map((t) => t.deviceId), ['phone']);

      now = now.add(const Duration(minutes: 7));
      await session.stopForeignTimer('phone');

      expect(session.foreignTimers, isEmpty);
      final logged = session.document.entries.values.single;
      expect(logged.start, startedAt);
      expect(logged.stop, now);
      expect(logged.description, 'call');

      final stored = onDisk(dirA);
      expect(stored.runningTimers, isEmpty);
      expect(stored.entries.values.single.stop, now);
      // The tombstone is what stops the other device's next merge from
      // resurrecting the timer this stop just closed.
      expect(stored.tombstones.containsKey('phone'), isTrue);
    });

    test('stopForeignTimer rides the commit queue with everything '
        'else', () async {
      final (session, _) = await openAt(dirA);
      await writeExternal(dirA, (doc) => doc.put(foreignTimer('phone', now)));
      await session.refresh();

      // Fired without awaiting: the queue must serialize them into two
      // complete read-merge-write cycles, losing neither.
      now = now.add(const Duration(minutes: 1));
      final mutation = session.put(entry('local-work'));
      final stop = session.stopForeignTimer('phone');
      await mutation;
      await stop;

      expect(session.document.entries.length, 2);
      final stored = onDisk(dirA);
      expect(stored.entries.length, 2);
      expect(stored.runningTimers, isEmpty);
    });

    test('acknowledgment hides exactly the seen set and re-arms for a '
        'different timer', () async {
      final (session, _) = await openAt(dirA);
      expect(session.hasUnacknowledgedForeignTimers, isFalse);

      final firstStart = DateTime.utc(2026, 8, 13, 8);
      await writeExternal(
        dirA,
        (doc) => doc.put(foreignTimer('phone', firstStart)),
      );
      await session.refresh();
      expect(session.hasUnacknowledgedForeignTimers, isTrue);

      session.acknowledgeForeignTimers();
      expect(session.hasUnacknowledgedForeignTimers, isFalse);

      // The same set arriving again changes nothing.
      await session.refresh();
      expect(session.hasUnacknowledgedForeignTimers, isFalse);

      // The same device restarting its timer is a new fact: same id, new
      // startedAt, and the question is owed again.
      final secondStart = DateTime.utc(2026, 8, 13, 10);
      await writeExternal(
        dirA,
        (doc) => doc.put(foreignTimer('phone', secondStart)),
      );
      await session.refresh();
      expect(session.hasUnacknowledgedForeignTimers, isTrue);
    });

    test('lastRefreshNewEntryIds names exactly the merged entries, and is '
        'replaced by the next refresh that brings some', () async {
      final (session, _) = await openAt(dirA);
      await session.put(entry('mine'));
      expect(session.lastRefreshNewEntryIds, isEmpty);

      await writeExternal(
        dirA,
        (doc) => doc
            .put(entry('theirs-1', minute: 10))
            .put(entry('theirs-2', minute: 20))
            .put(Client(id: 'acme', modified: now, name: 'Acme')),
      );
      await session.refresh();

      // Entries only — the client counts toward lastRefreshNewRecords but is
      // not a row the timer list could tint.
      expect(
        session.lastRefreshNewEntryIds,
        unorderedEquals(['theirs-1', 'theirs-2']),
      );
      expect(session.lastRefreshNewRecords, 3);

      // An empty-handed refresh leaves the marks standing: reads come a couple
      // of seconds apart after a resume, and clearing on those would take the
      // marks away before anyone could read them.
      await session.refresh();
      expect(
        session.lastRefreshNewEntryIds,
        unorderedEquals(['theirs-1', 'theirs-2']),
      );
      expect(session.lastRefreshNewRecords, 0);

      // A refresh that does bring something replaces them outright.
      await writeExternal(
        dirA,
        (doc) => doc.put(entry('theirs-3', minute: 30)),
      );
      await session.refresh();
      expect(session.lastRefreshNewEntryIds, ['theirs-3']);
    });
  });

  group('folder watcher', () {
    const locationA = DocumentLocation(handle: 'memory:watch-a', label: 'A');
    const locationB = DocumentLocation(handle: 'memory:watch-b', label: 'B');

    /// An open session over the in-memory fake, whose watch stream stands in
    /// for the platform's — the NSFilePresenter on the two Apple platforms,
    /// nothing at all on the other three (§4.1).
    Future<(DocumentSession, DocumentLocationPreference, FakeDocumentDirectory)>
    openWatched() async {
      final directory = FakeDocumentDirectory();
      final preference = await DocumentLocationPreference.load();
      await preference.set(locationA);
      final session = DocumentSession(
        directory: directory,
        locationPreference: preference,
        clock: () => now,
        deviceId: 'device-a',
      );
      await session.open();
      return (session, preference, directory);
    }

    Future<void> writeAsOtherDevice(
      FakeDocumentDirectory directory,
      DocumentLocation location,
      String id,
    ) async {
      final other = DocumentRepository(store: directory.storeAt(location));
      await other.load();
      await other.save(CirrhyDocument.empty().put(entry(id)));
    }

    /// Waits out the settle window the session gives a burst of events. Real
    /// time rather than a fake clock: this is a plain test, and the margin
    /// over the microtask-speed fake store is enormous.
    Future<void> settle() =>
        Future<void>.delayed(DocumentSession.watchSettle * 3);

    test('the folder saying it changed is a re-read, without waiting for the '
        'schedule', () async {
      final (session, _, directory) = await openWatched();
      addTearDown(session.dispose);
      expect(directory.watched, [locationA]);
      expect(session.document.entries, isEmpty);

      await writeAsOtherDevice(directory, locationA, 'theirs');
      directory.announceChange();
      await settle();
      await session.idle;

      expect(session.document.entries.keys, ['theirs']);
      expect(session.lastRefreshNewRecords, 1);
    });

    test('a burst of events costs one re-read, not one each', () async {
      final (session, _, directory) = await openWatched();
      addTearDown(session.dispose);
      final store = directory.storeAt(locationA);
      final before = store.reads;

      // One write is reported several times — the item changed, a subitem
      // changed, something moved into place. They all want the same answer,
      // and the answer is worth taking after the last of them, not during.
      directory.announceChange();
      directory.announceChange();
      directory.announceChange();
      await pumpEventQueue();
      expect(store.reads, before, reason: 'still settling');

      await settle();
      await session.idle;

      expect(store.reads, before + 1);
    });

    test('the watch follows the document to a new folder and lets go of the '
        'old one', () async {
      final (session, preference, directory) = await openWatched();
      addTearDown(session.dispose);

      await preference.set(locationB);
      await session.idle;

      expect(directory.watched, [locationA, locationB]);
      expect(directory.liveWatchers, 1, reason: 'the old one was let go');

      await writeAsOtherDevice(directory, locationB, 'theirs');
      directory.announceChange();
      await settle();
      await session.idle;

      expect(session.document.entries.keys, ['theirs']);
    });

    test('a cleared location stops the watching', () async {
      final (session, preference, directory) = await openWatched();
      addTearDown(session.dispose);

      // §4.4's forced re-pick: the handle went bad and was cleared.
      await preference.clear();
      await session.idle;

      expect(directory.liveWatchers, 0);
    });

    test('disposing lets go of the folder', () async {
      final (session, _, directory) = await openWatched();
      expect(directory.liveWatchers, 1);

      session.dispose();
      await pumpEventQueue();

      expect(directory.liveWatchers, 0);
      // And nothing is listening, so a late event cannot reach a disposed
      // session's notifyListeners — nor leave a settle timer behind it.
      directory.announceChange();
      await settle();
    });
  });

  group('blocked saves', () {
    test('an unreadable file blocks the save but never the session', () async {
      final (session, _) = await openAt(dirA);
      await session.put(Client(id: 'acme', modified: now, name: 'Acme'));
      final goodBytes = fileIn(dirA).readAsBytesSync();

      // Something corrupts the file behind our back.
      fileIn(dirA).writeAsStringSync('not a document {{{');

      now = now.add(const Duration(minutes: 1));
      await session.startTimer(description: 'tracked');

      // The engine refused to overwrite what it cannot read (fail closed),
      // and the session kept the change in memory instead of dropping it.
      expect(session.lastError, isA<SaveBlockedException>());
      expect(session.myTimer, isNotNull);
      expect(
        fileIn(dirA).readAsStringSync(),
        'not a document {{{',
        reason: 'a blocked save must not have touched the file',
      );

      // The file becomes readable again — restored from a backup, or a sync
      // client delivers a good copy. The next commit persists everything.
      fileIn(dirA).writeAsBytesSync(goodBytes);
      now = now.add(const Duration(minutes: 1));
      await session.put(
        Project(
          id: 'p1',
          modified: now,
          name: 'Cirrhy',
          clientId: 'acme',
          locationChanged: now,
        ),
      );

      expect(session.lastError, isNull);
      final stored = onDisk(dirA);
      expect(stored.clients.keys, ['acme']);
      expect(stored.projects.keys, ['p1']);
      expect(stored.runningTimers.values.single.description, 'tracked');
    });
  });

  group('device id', () {
    test('is minted once and persisted across start() calls', () async {
      final preference = await DocumentLocationPreference.load();
      final directory = FakeDocumentDirectory();

      final first = await DocumentSession.start(
        directory: directory,
        locationPreference: preference,
      );
      addTearDown(first.dispose);
      final second = await DocumentSession.start(
        directory: directory,
        locationPreference: preference,
      );
      addTearDown(second.dispose);

      expect(first.deviceId, isNotEmpty);
      expect(second.deviceId, first.deviceId);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('device.id'), first.deviceId);
    });

    test('an explicitly provided id wins over the stored one', () async {
      SharedPreferences.setMockInitialValues({'device.id': 'stored'});
      final session = await DocumentSession.start(
        directory: FakeDocumentDirectory(),
        locationPreference: await DocumentLocationPreference.load(),
        deviceId: 'explicit',
      );
      addTearDown(session.dispose);

      expect(session.deviceId, 'explicit');
    });
  });

  group('refresher', () {
    const location = DocumentLocation(handle: 'memory:a', label: 'A');

    /// An open session over the in-memory fake — real file IO cannot settle
    /// inside testWidgets' fake-async zone, the memory store can.
    Future<(DocumentSession, FakeDocumentDirectory)> memorySession() async {
      final directory = FakeDocumentDirectory();
      final preference = await DocumentLocationPreference.load();
      await preference.set(location);
      final session = DocumentSession(
        directory: directory,
        locationPreference: preference,
        clock: () => now,
        deviceId: 'device-a',
      );
      await session.open();
      return (session, directory);
    }

    Future<void> pumpShell(WidgetTester tester, DocumentSession? session) =>
        tester.pumpWidget(
          MaterialApp(
            theme: cirrhyLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: AppShell(session: session),
          ),
        );

    /// The other machine's save, arriving through a sync client: its own
    /// repository over the same store.
    Future<void> writeAsOtherDevice(
      FakeDocumentDirectory directory,
      String id,
    ) async {
      final other = DocumentRepository(store: directory.storeAt(location));
      await other.load();
      await other.save(CirrhyDocument.empty().put(entry(id)));
    }

    testWidgets('the shell hooks it exactly when a session exists', (
      tester,
    ) async {
      await pumpShell(tester, null);
      expect(find.byType(SessionRefresher), findsNothing);

      final (session, _) = await memorySession();
      addTearDown(session.dispose);
      await pumpShell(tester, session);
      expect(find.byType(SessionRefresher), findsOneWidget);
    });

    testWidgets('resuming the app merges what changed on disk', (tester) async {
      final (session, directory) = await memorySession();
      addTearDown(session.dispose);
      await pumpShell(tester, session);
      expect(session.document.entries, isEmpty);

      // A sync client wrote while the app was backgrounded.
      await writeAsOtherDevice(directory, 'synced');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(session.document.entries.keys, ['synced']);
      expect(session.lastRefreshNewRecords, 1);
    });

    testWidgets('a file delivered just after the resume read is still caught', (
      tester,
    ) async {
      final (session, directory) = await memorySession();
      addTearDown(session.dispose);
      await pumpShell(tester, session);

      // Coming forward finds the old file: the provider is still fetching.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(session.document.entries, isEmpty);

      // It lands moments later, with nothing at all to announce it. This is
      // the case the resume-only version could never see.
      await writeAsOtherDevice(directory, 'late');
      await tester.pump(SessionRefresher.settling.first);

      expect(session.document.entries.keys, ['late']);
    });

    testWidgets('the reads keep coming while the app sits open', (
      tester,
    ) async {
      final (session, directory) = await memorySession();
      addTearDown(session.dispose);
      await pumpShell(tester, session);

      // Past the settling burst and into the steady interval.
      var elapsed = Duration.zero;
      for (final delay in SessionRefresher.settling) {
        elapsed += delay;
      }
      await tester.pump(elapsed);

      await writeAsOtherDevice(directory, 'while-watching');
      await tester.pump(SessionRefresher.steady);

      expect(session.document.entries.keys, ['while-watching']);
    });

    /// The framework asserts on lifecycle jumps, so leaving and returning are
    /// walked one state at a time exactly as the engine reports them.
    void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
      for (final state in states) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    testWidgets('nothing is read behind the app, and resuming starts again', (
      tester,
    ) async {
      final (session, directory) = await memorySession();
      addTearDown(session.dispose);
      await pumpShell(tester, session);

      lifecycle(tester, [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      await tester.pump();

      final store = directory.storeAt(location);
      await writeAsOtherDevice(directory, 'while-away');
      final readsWhenBackgrounded = store.reads;
      await tester.pump(const Duration(minutes: 5));

      expect(store.reads, readsWhenBackgrounded, reason: 'no reads while away');
      expect(session.document.entries, isEmpty);

      lifecycle(tester, [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await tester.pump();

      expect(session.document.entries.keys, ['while-away']);
    });
  });
}
