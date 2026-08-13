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

import 'package:cirrhy/storage/document_backups.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/storage/path_document_directory.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The claims DESIGN.md §4.6 makes about moving the file, against real files
/// rather than a memory store.
///
/// Relocating and setting up a second device are the same operation from the
/// engine's side, and both come down to read-merge-write (§3.2) doing the
/// right thing against a folder that already holds someone else's history.
void main() {
  late Directory first;
  late Directory second;
  late Directory backupDir;

  DocumentLocation locate(Directory dir) =>
      DocumentLocation(handle: dir.path, label: dir.path);

  DocumentRepository repoAt(Directory dir) => DocumentRepository(
    store: PathDocumentStore(locate(dir)),
    backup: DocumentBackups(backupDir),
  );

  TimeEntry entry(String id, int minute) => TimeEntry(
    id: id,
    modified: DateTime.utc(2026, 8, 13, 9, minute),
    start: DateTime.utc(2026, 8, 13, 9, minute),
    stop: DateTime.utc(2026, 8, 13, 10, minute),
    projectId: null,
    locationChanged: DateTime.utc(2026, 8, 13, 9, minute),
    description: id,
  );

  setUp(() {
    first = Directory.systemTemp.createTempSync('cirrhy_first');
    second = Directory.systemTemp.createTempSync('cirrhy_second');
    backupDir = Directory.systemTemp.createTempSync('cirrhy_backups');
  });

  tearDown(() {
    for (final dir in [first, second, backupDir]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  test('a first save creates the document in the chosen folder', () async {
    final repo = repoAt(first);
    await repo.load();

    await repo.save(const CirrhyDocument.empty().put(entry('monday', 0)));

    final file = File(p.join(first.path, documentFileName));
    expect(file.existsSync(), isTrue);
    expect(
      const JsonDocumentCodec().decode(file.readAsBytesSync()).entries.keys,
      ['monday'],
    );
  });

  // The adopt rule (§4.6) and the second-device case, which are the same
  // thing: point at a folder that already holds a document and the histories
  // join. Nothing is overwritten in either direction.
  test(
    'relocating into an occupied folder merges instead of replacing',
    () async {
      // The laptop.
      final laptop = repoAt(first);
      await laptop.load();
      var mine = const CirrhyDocument.empty().put(entry('laptop-work', 0));
      mine = await laptop.save(mine);

      // The phone's folder already has its own history, synced in from
      // elsewhere and never seen by this device.
      final phone = repoAt(second);
      await phone.load();
      await phone.save(
        const CirrhyDocument.empty().put(entry('phone-work', 5)),
      );

      // The user moves the laptop's folder to the phone's.
      final moved = repoAt(second);
      final result = await moved.save(mine);

      expect(
        result.entries.keys,
        unorderedEquals(['laptop-work', 'phone-work']),
        reason: 'the document the folder already held must survive the move',
      );
      final onDisk = const JsonDocumentCodec().decode(
        File(p.join(second.path, documentFileName)).readAsBytesSync(),
      );
      expect(
        onDisk.entries.keys,
        unorderedEquals(['laptop-work', 'phone-work']),
      );
    },
  );

  test('the old folder is left untouched by the move', () async {
    final laptop = repoAt(first);
    await laptop.load();
    final mine = await laptop.save(
      const CirrhyDocument.empty().put(entry('laptop-work', 0)),
    );

    await repoAt(second).save(mine);

    // Deleting a file inside someone's sync folder is not ours to do (§4.6),
    // and because the merge is a union, re-picking it later costs nothing.
    expect(File(p.join(first.path, documentFileName)).existsSync(), isTrue);
  });

  test('every overwrite leaves the previous state recoverable', () async {
    final repo = repoAt(first);
    await repo.load();
    var doc = const CirrhyDocument.empty().put(entry('first', 0));
    doc = await repo.save(doc);
    await repo.save(doc.put(entry('second', 5)));

    // The backup holds what was there *before* the second write, which is the
    // state a torn write or a bad merge would have destroyed. On Android this
    // is the whole recovery story, since SAF cannot replace atomically (§4.3).
    final backups = await DocumentBackups(backupDir).list();
    expect(backups, hasLength(1));
    expect(
      const JsonDocumentCodec()
          .decode(backups.single.readAsBytesSync())
          .entries
          .keys,
      ['first'],
    );
  });

  test(
    'a save survives a document another device rewrote underneath',
    () async {
      final repo = repoAt(first);
      var mine = await repo.load();
      mine = mine.put(entry('mine', 0));

      // A sync client drops in a newer file between our load and our save.
      final theirs = const CirrhyDocument.empty().put(entry('theirs', 5));
      File(
        p.join(first.path, documentFileName),
      ).writeAsBytesSync(const JsonDocumentCodec().encode(theirs));

      final saved = await repo.save(mine);

      expect(saved.entries.keys, unorderedEquals(['mine', 'theirs']));
    },
  );
}
