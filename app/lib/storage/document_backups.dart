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

import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps the last few states of the document in app-private storage.
///
/// DESIGN.md §4.2 and §4.3. Written immediately before each overwrite, so a
/// save that tears leaves the previous state intact somewhere. On Android that
/// is the entire recovery story, because SAF cannot replace a file atomically
/// and every save is an in-place overwrite.
///
/// Plain `dart:io` on all five platforms, and deliberately not part of the
/// platform channel: `getApplicationSupportDirectory` resolves to a real
/// filesystem path everywhere, including the two platforms where the *user's*
/// folder is reachable only through a bookmark or a content URI.
///
/// App-private, not beside the document. A backup that lives in the synced
/// folder is exposed to the same sync client that caused the problem it exists
/// to survive, and it would upload copies of the whole file on every save.
/// §4.6 leaves a beside-the-file option to settings, off by default.
final class DocumentBackups implements DocumentBackup {
  DocumentBackups(this.directory, {this.keep = 3});

  /// Where the snapshots go. Injectable so tests can use a temp directory
  /// instead of a plugin.
  final Directory directory;

  /// How many to retain. Three covers the realistic case — noticing after the
  /// save that followed the bad one — without turning a per-save copy into
  /// unbounded growth.
  final int keep;

  static const _prefix = 'cirrhy-';
  static const _suffix = '.json';

  /// Opens (and creates) the app-private backup directory.
  static Future<DocumentBackups> openAppPrivate({int keep = 3}) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'backups'));
    await dir.create(recursive: true);
    return DocumentBackups(dir, keep: keep);
  }

  @override
  Future<void> snapshot(List<int> bytes) async {
    await directory.create(recursive: true);
    final file = await _freeName(DateTime.now().toUtc());
    await file.writeAsBytes(bytes, flush: true);
    await prune();
  }

  /// Newest first.
  Future<List<File>> list() async {
    if (!await directory.exists()) return const <File>[];
    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith(_prefix) && name.endsWith(_suffix)) files.add(entity);
    }
    // The stamp is fixed-width UTC, so lexicographic order is chronological
    // order. Sorting by name rather than mtime keeps this honest across a
    // sync client that rewrites timestamps.
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return files;
  }

  Future<void> prune() async {
    final files = await list();
    for (final file in files.skip(keep)) {
      try {
        await file.delete();
      } on FileSystemException {
        // A backup we failed to delete costs disk, not data.
      }
    }
  }

  /// The first unused `cirrhy-20260813T101500123Z-00.json`.
  ///
  /// The timestamp is not assumed to be unique. Two saves inside the same
  /// millisecond are perfectly reachable — stopping a timer and editing the
  /// entry it produced, or any loop — and a name that collided would silently
  /// leave one fewer backup than the count promises. The counter is padded and
  /// always present so that lexicographic order stays chronological order,
  /// which is what [list] sorts on.
  Future<File> _freeName(DateTime utc) async {
    final stamp = _stamp(utc);
    for (var i = 0; i < 100; i++) {
      final candidate = File(
        p.join(directory.path, '$_prefix$stamp-${_pad(i)}$_suffix'),
      );
      if (!await candidate.exists()) return candidate;
    }
    // A hundred snapshots inside one millisecond is not a real scenario; if it
    // somehow happens, reusing the last name loses a backup rather than
    // failing the save.
    return File(p.join(directory.path, '$_prefix$stamp-99$_suffix'));
  }

  static String _pad(int value, [int width = 2]) =>
      value.toString().padLeft(width, '0');

  static String _stamp(DateTime utc) =>
      '${utc.year}${_pad(utc.month)}${_pad(utc.day)}'
      'T${_pad(utc.hour)}${_pad(utc.minute)}${_pad(utc.second)}'
      '${_pad(utc.millisecond, 3)}Z';
}
