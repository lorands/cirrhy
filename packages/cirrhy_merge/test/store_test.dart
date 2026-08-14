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

import 'dart:convert';

import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:test/test.dart';

import 'merge_test.dart' show entry, t;

/// Stands in for the OS file handle (DESIGN.md §4.1) so the read-merge-write
/// loop can be tested without any platform involved.
final class MemoryStore implements DocumentStore {
  List<int> bytes = const [];
  int reads = 0;
  int writes = 0;

  @override
  Future<StoredBytes> read() async {
    reads++;
    return StoredBytes.of(bytes);
  }

  @override
  Future<void> write(List<int> data) async {
    writes++;
    bytes = data;
  }
}

void main() {
  group('codec', () {
    test('round-trips a populated document', () {
      const codec = JsonDocumentCodec();
      final doc = const CirrhyDocument.empty()
          .put(Client(id: 'c1', modified: t(1), name: 'Acme Corp'))
          .put(
            Project(
              id: 'p1',
              modified: t(2),
              name: 'Website',
              clientId: 'c1',
              locationChanged: t(2),
              color: '#0E9F6E',
            ),
          )
          .put(entry('e1', mod: 10, start: 9, stop: 11, desc: 'design review'))
          .delete('gone', t(5));

      final back = codec.decode(codec.encode(doc));

      expect(back.clients['c1']!.name, 'Acme Corp');
      expect(back.projects['p1']!.clientId, 'c1');
      expect(back.projects['p1']!.color, '#0E9F6E');
      expect(back.entries['e1']!.duration, const Duration(minutes: 2));
      expect(back.tombstones['gone']!.deletedAt, t(5));
    });

    test('round-trips history', () {
      const codec = JsonDocumentCodec();
      final merged = const CirrhyDocument.empty().put(
        entry('e1', mod: 10, start: 9, desc: 'first'),
      );
      final withHistory = mergeDocuments(
        merged,
        const CirrhyDocument.empty().put(
          entry('e1', mod: 20, start: 9, desc: 'second'),
        ),
      );

      final back = codec.decode(codec.encode(withHistory));

      expect(back.entries['e1']!.description, 'second');
      expect(back.entries['e1']!.history.single.fields['description'], 'first');
    });

    test('encoding is byte-stable, so the content hash is meaningful', () {
      const codec = JsonDocumentCodec();
      final doc = const CirrhyDocument.empty()
          .put(entry('e2', mod: 10, start: 9))
          .put(entry('e1', mod: 11, start: 9));

      expect(contentHash(codec.encode(doc)), contentHash(codec.encode(doc)));
    });

    test('empty bytes decode to an empty document', () {
      expect(const JsonDocumentCodec().decode(const []).recordCount, 0);
    });

    test('refuses a file it did not write', () {
      expect(
        () => const JsonDocumentCodec().decode(utf8.encode('{"format":"x"}')),
        throwsA(isA<DocumentFormatException>()),
      );
    });

    test(
      'refuses a future format version rather than writing it back lossily',
      () {
        final future = utf8.encode('{"format":"cirrhy","formatVersion":99}');
        expect(
          () => const JsonDocumentCodec().decode(future),
          throwsA(isA<DocumentFormatException>()),
        );
      },
    );
  });

  group('read-merge-write', () {
    test('a first save writes the document', () async {
      final store = MemoryStore();
      final repo = DocumentRepository(store: store);
      await repo.load();

      final doc = const CirrhyDocument.empty().put(
        entry('e1', mod: 10, start: 9),
      );
      await repo.save(doc);

      expect(store.writes, 1);
      expect(
        const JsonDocumentCodec().decode(store.bytes).entries,
        hasLength(1),
      );
    });

    test(
      'a peer write landing between load and save is merged, not clobbered',
      () async {
        final store = MemoryStore();
        final repo = DocumentRepository(store: store);

        var mine = await repo.load();
        mine = mine.put(entry('mine', mod: 10, start: 9));

        // Another device writes the shared file while we were editing.
        store.bytes = const JsonDocumentCodec().encode(
          const CirrhyDocument.empty().put(entry('theirs', mod: 11, start: 9)),
        );

        final saved = await repo.save(mine);

        expect(
          saved.entries.keys,
          unorderedEquals(['mine', 'theirs']),
          reason: 'the peer entry must survive our save',
        );
        final onDisk = const JsonDocumentCodec().decode(store.bytes);
        expect(onDisk.entries.keys, unorderedEquals(['mine', 'theirs']));
      },
    );

    test('refuses to overwrite a file it cannot parse', () async {
      // Failing closed matters: treating an unreadable file as empty and
      // merging into it would write the user's entire history away.
      final store = MemoryStore()..bytes = utf8.encode('not json at all');
      final repo = DocumentRepository(store: store);

      expect(
        () => repo.save(const CirrhyDocument.empty()),
        throwsA(isA<SaveBlockedException>()),
      );
      expect(store.writes, 0);
    });

    test('refresh merges external changes without writing', () async {
      final store = MemoryStore();
      final repo = DocumentRepository(store: store);
      var mine = await repo.load();
      mine = mine.put(entry('mine', mod: 10, start: 9));

      store.bytes = const JsonDocumentCodec().encode(
        const CirrhyDocument.empty().put(entry('theirs', mod: 11, start: 9)),
      );

      final refreshed = await repo.refresh(mine);

      expect(refreshed.entries.keys, unorderedEquals(['mine', 'theirs']));
      expect(store.writes, 0, reason: 'refresh must not write');
    });

    test('an unchanged file still gets re-read on every save', () async {
      // Nothing notifies us that the file changed (DESIGN.md §4.4) and mtime is
      // not trustworthy (§3.2), so the read is unconditional.
      final store = MemoryStore();
      final repo = DocumentRepository(store: store);
      await repo.load();
      final before = store.reads;

      await repo.save(const CirrhyDocument.empty());

      expect(store.reads, before + 1);
    });
  });

  group('pre-write backup', () {
    test('snapshots what was on disk before overwriting it', () async {
      final store = MemoryStore();
      final backup = RecordingBackup();
      final repo = DocumentRepository(store: store, backup: backup);
      await repo.save(
        const CirrhyDocument.empty().put(entry('first', mod: 1, start: 1)),
      );

      await repo.save(
        const CirrhyDocument.empty().put(entry('second', mod: 2, start: 2)),
      );

      // The *previous* state, not the one being written. The point is to hold
      // the last bytes known to be readable, which is what a torn write or a
      // bad merge destroys.
      expect(backup.snapshots, hasLength(1));
      final restored = const JsonDocumentCodec().decode(
        backup.snapshots.single,
      );
      expect(restored.entries.keys, ['first']);
    });

    test('has nothing to snapshot on the first ever write', () async {
      final backup = RecordingBackup();
      await DocumentRepository(
        store: MemoryStore(),
        backup: backup,
      ).save(const CirrhyDocument.empty());

      expect(backup.snapshots, isEmpty);
    });

    test('a failed backup does not fail the save', () async {
      // Refusing to write because the snapshot failed discards the interval
      // the user just tracked — a certain loss — to guard against a torn
      // write, which is a possible one.
      final store = MemoryStore();
      final repo = DocumentRepository(store: store, backup: BrokenBackup());
      await repo.save(
        const CirrhyDocument.empty().put(entry('first', mod: 1, start: 1)),
      );

      await repo.save(
        const CirrhyDocument.empty().put(entry('second', mod: 2, start: 2)),
      );

      expect(store.writes, 2);
      expect(const JsonDocumentCodec().decode(store.bytes).entries.keys, [
        'second',
      ]);
    });
  });
}

/// Captures the bytes handed to it, in order.
final class RecordingBackup implements DocumentBackup {
  final List<List<int>> snapshots = [];

  @override
  Future<void> snapshot(List<int> bytes) async => snapshots.add(bytes);
}

/// App-private storage that is full, unwritable, or otherwise having a bad day.
final class BrokenBackup implements DocumentBackup {
  @override
  Future<void> snapshot(List<int> bytes) async =>
      throw StateError('no space left on device');
}
