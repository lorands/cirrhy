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
import 'package:cirrhy/settings/document_location_preference.dart';
import 'package:cirrhy/storage/document_directory.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/storage/path_document_directory.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// The manual beside-the-file backup of DESIGN.md §11, against a real folder.
///
/// The promises under test are §11's own: the copy is the on-disk bytes after
/// the commit queue has flushed, a same-day repeat gets a numbered name
/// instead of overwriting, and the copies are inert — the adopt rule does not
/// see them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = JsonDocumentCodec();

  late Directory dir;

  /// The controllable clock. Backup names use its local date as given.
  var now = DateTime.utc(2026, 8, 15, 9);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 8, 15, 9);
    dir = Directory.systemTemp.createTempSync('cirrhy_backup');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File fileIn(String name) => File(p.join(dir.path, name));

  Future<DocumentSession> openSession() async {
    final preference = await DocumentLocationPreference.load();
    await preference.set(DocumentLocation(handle: dir.path, label: dir.path));
    final session = DocumentSession(
      directory: const PathDocumentDirectory(),
      locationPreference: preference,
      clock: () => now,
      deviceId: 'device-a',
    );
    addTearDown(session.dispose);
    await session.open();
    return session;
  }

  Client client(String id) =>
      Client(id: id, modified: DateTime.utc(2026, 8, 15, 8), name: id);

  test('copies the on-disk bytes, byte for byte, under a dated name', () async {
    final session = await openSession();
    await session.put(client('acme'));

    final name = await session.backUpNow();

    expect(name, 'cirrhy-backup-2026-08-15.json');
    expect(
      fileIn(name!).readAsBytesSync(),
      fileIn(documentFileName).readAsBytesSync(),
    );
  });

  test('a same-day repeat gets a numbered name, never an overwrite', () async {
    final session = await openSession();
    await session.put(client('acme'));
    final first = await session.backUpNow();
    final firstBytes = fileIn(first!).readAsBytesSync();

    await session.put(client('globex'));
    final second = await session.backUpNow();

    expect(second, 'cirrhy-backup-2026-08-15-2.json');
    expect(await session.backUpNow(), 'cirrhy-backup-2026-08-15-3.json');
    // The copy the user deliberately took is untouched (§11).
    expect(fileIn(first).readAsBytesSync(), firstBytes);
  });

  test('a later day starts a fresh date, not a higher number', () async {
    final session = await openSession();
    await session.put(client('acme'));
    await session.backUpNow();

    now = DateTime.utc(2026, 8, 16, 9);

    expect(await session.backUpNow(), 'cirrhy-backup-2026-08-16.json');
  });

  test('queues behind pending commits, so the copy holds them', () async {
    final session = await openSession();
    await session.put(client('acme'));

    // Not awaited: the commit is still in the queue when the backup is asked
    // for. §11 promises the copy is what is durably true *after* the queue
    // flushes, so the entry must be in it.
    final pending = session.put(client('globex'));
    final name = await session.backUpNow();
    await pending;

    final copied = codec.decode(fileIn(name!).readAsBytesSync());
    expect(copied.clients.keys, containsAll(['acme', 'globex']));
  });

  test('nothing on disk yet answers null and writes nothing', () async {
    final session = await openSession();

    expect(await session.backUpNow(), isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('an unreachable folder throws, like any save', () async {
    final session = await openSession();
    await session.put(client('acme'));
    dir.deleteSync(recursive: true);

    expect(session.backUpNow(), throwsA(isA<DocumentLocationUnavailable>()));
  });

  test('backups are inert: the adopt rule does not see them', () async {
    final session = await openSession();
    await session.put(client('acme'));
    await session.backUpNow();

    // Only the document itself is a known name (§11): a folder holding
    // nothing but backups is "will create", never "will adopt", and no code
    // path reads a backup back.
    final found = await const PathDocumentDirectory().existingDocuments(
      DocumentLocation(handle: dir.path, label: dir.path),
    );
    expect(found, [documentFileName]);
  });
}
