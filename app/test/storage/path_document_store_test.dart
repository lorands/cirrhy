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
import 'dart:io';

import 'package:cirrhy/storage/document_directory.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/storage/path_document_directory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory folder;
  late DocumentLocation location;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('cirrhy_store_test');
    location = DocumentLocation(handle: folder.path, label: folder.path);
  });

  tearDown(() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  File document() => File(p.join(folder.path, documentFileName));

  group('PathDocumentStore', () {
    test('an empty folder reads as an empty document', () async {
      final stored = await PathDocumentStore(location).read();
      expect(stored.bytes, isEmpty);
    });

    test('round-trips bytes', () async {
      final store = PathDocumentStore(location);
      await store.write(utf8.encode('{"format":"cirrhy"}'));

      expect(utf8.decode((await store.read()).bytes), '{"format":"cirrhy"}');
    });

    test('leaves no temp file behind', () async {
      await PathDocumentStore(location).write(utf8.encode('x'));

      final names = folder
          .listSync()
          .map((e) => p.basename(e.path))
          .toList(growable: false);
      expect(names, [documentFileName]);
    });

    test('replaces rather than appends on a second write', () async {
      final store = PathDocumentStore(location);
      await store.write(utf8.encode('the first document'));
      await store.write(utf8.encode('short'));

      expect(utf8.decode((await store.read()).bytes), 'short');
    });

    // §4.4: a handle can stop resolving — a folder deleted, an iOS bookmark
    // gone stale, an Android permission revoked. It must never look like an
    // empty document, because the next save would merge into nothing and
    // write the user's entire history away.
    test('a folder that has gone away is not an empty document', () async {
      final store = PathDocumentStore(location);
      await store.write(utf8.encode('real data'));
      folder.deleteSync(recursive: true);

      await expectLater(
        store.read(),
        throwsA(isA<DocumentLocationUnavailable>()),
      );
    });

    test('refuses to write to a folder that has gone away', () async {
      final store = PathDocumentStore(location);
      folder.deleteSync(recursive: true);

      await expectLater(
        store.write(utf8.encode('x')),
        throwsA(isA<DocumentLocationUnavailable>()),
      );
    });

    test('sweeps a temp file an earlier crash left behind', () async {
      // Old enough that no live save could still hold it. These sit in a
      // folder the user is looking at and a sync client is uploading, so
      // leaving them is not harmless.
      final stale = File(p.join(folder.path, '${documentTempPrefix}999'))
        ..writeAsBytesSync(utf8.encode('half a document'))
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 2)),
        );

      await PathDocumentStore(location).write(utf8.encode('x'));

      expect(stale.existsSync(), isFalse);
    });

    test('leaves a temp file recent enough to be a live save', () async {
      final live = File(p.join(folder.path, '${documentTempPrefix}998'))
        ..writeAsBytesSync(utf8.encode('another instance is mid-write'));

      await PathDocumentStore(location).write(utf8.encode('x'));

      expect(live.existsSync(), isTrue);
    });
  });

  group('PathDocumentDirectory', () {
    const directory = PathDocumentDirectory();

    test('reports an existing folder as available', () async {
      expect(await directory.isAvailable(location), isTrue);
    });

    test('reports a deleted folder as unavailable', () async {
      folder.deleteSync(recursive: true);
      expect(await directory.isAvailable(location), isFalse);
    });

    test('finds nothing in an empty folder', () async {
      expect(await directory.existingDocuments(location), isEmpty);
    });

    // The adopt rule of §4.6: this is how setting up the second device stays
    // the same flow as the first, instead of asking "new or existing?".
    test('finds a document already in the folder', () async {
      document().writeAsStringSync('{}');
      expect(await directory.existingDocuments(location), [documentFileName]);
    });

    test('ignores files that are not the document', () async {
      File(p.join(folder.path, 'notes.txt')).writeAsStringSync('hello');
      expect(await directory.existingDocuments(location), isEmpty);
    });
  });
}
