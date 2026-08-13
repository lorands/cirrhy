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

import 'package:cirrhy/storage/document_backups.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('cirrhy_backup_test'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('DocumentBackups', () {
    test('writes the bytes it was handed', () async {
      await DocumentBackups(dir).snapshot(utf8.encode('previous state'));

      final files = await DocumentBackups(dir).list();
      expect(files, hasLength(1));
      expect(utf8.decode(files.single.readAsBytesSync()), 'previous state');
    });

    test('creates the directory if it is missing', () async {
      dir.deleteSync(recursive: true);
      await DocumentBackups(dir).snapshot(utf8.encode('x'));

      expect(await DocumentBackups(dir).list(), hasLength(1));
    });

    // Two saves in quick succession are ordinary — stopping a timer and then
    // editing the entry it produced. The name must not rely on the clock
    // ticking between them, or one save silently overwrites the other's
    // backup and there is one fewer than the count promises.
    test('keeps snapshots taken in the same instant apart', () async {
      final backups = DocumentBackups(dir);
      await backups.snapshot(utf8.encode('one'));
      await backups.snapshot(utf8.encode('two'));

      expect(await backups.list(), hasLength(2));
    });

    test('keeps only the newest few', () async {
      final backups = DocumentBackups(dir, keep: 3);
      for (var i = 0; i < 6; i++) {
        await backups.snapshot(utf8.encode('state $i'));
      }

      final files = await backups.list();
      expect(files, hasLength(3));
      // Newest first, and the newest is the last thing written.
      expect(utf8.decode(files.first.readAsBytesSync()), 'state 5');
    });

    test('ignores files it did not write', () async {
      File(p.join(dir.path, 'unrelated.json')).writeAsStringSync('{}');
      await DocumentBackups(dir, keep: 1).snapshot(utf8.encode('x'));

      final names = dir.listSync().map((e) => p.basename(e.path));
      expect(names, contains('unrelated.json'));
      expect(await DocumentBackups(dir).list(), hasLength(1));
    });
  });
}
