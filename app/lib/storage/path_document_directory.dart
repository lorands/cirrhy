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
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'document_directory.dart';
import 'document_location.dart';

/// Linux and Windows, where the handle is just a path.
///
/// Neither platform sandboxes a desktop app away from a folder the user
/// pointed at, so the path keeps working after a restart and there is nothing
/// to bookmark. macOS looks like it belongs here and does not — see the note
/// under DESIGN.md §4.1.
final class PathDocumentDirectory implements DocumentDirectory {
  const PathDocumentDirectory();

  @override
  Future<DocumentLocation?> pick() async {
    final path = await getDirectoryPath();
    if (path == null) return null;
    // The label is the path itself here. It is the one platform where the
    // handle happens to be readable, and a bare folder name would be less
    // useful than the full path when the user has several sync folders.
    return DocumentLocation(handle: path, label: path);
  }

  @override
  Future<bool> isAvailable(DocumentLocation location) =>
      Directory(location.handle).exists();

  @override
  Future<List<String>> existingDocuments(DocumentLocation location) async {
    final found = <String>[];
    for (final name in knownDocumentFileNames) {
      if (await File(p.join(location.handle, name)).exists()) found.add(name);
    }
    return found;
  }

  @override
  DocumentStore storeAt(DocumentLocation location) =>
      PathDocumentStore(location);
}

/// Reads and writes one file inside a directory the app can address by path.
///
/// Exposed rather than private so tests can point it at a temp directory
/// without a picker, a plugin, or a running platform channel.
final class PathDocumentStore implements DocumentStore {
  PathDocumentStore(this.location, {String fileName = documentFileName})
    : _path = p.join(location.handle, fileName);

  final DocumentLocation location;
  final String _path;

  @override
  Future<StoredBytes> read() async {
    final file = File(_path);
    try {
      if (!await file.exists()) {
        // Distinguish "no document yet" from "no folder": the first is the
        // normal first run, the second means the handle has gone bad and the
        // user has to be sent back to the picker rather than quietly given an
        // empty document to overwrite their history with.
        if (!await Directory(location.handle).exists()) {
          throw DocumentLocationUnavailable(location);
        }
        return StoredBytes.empty;
      }
      return StoredBytes.of(await file.readAsBytes());
    } on FileSystemException catch (e) {
      throw DocumentLocationUnavailable(location, e);
    }
  }

  /// Temp file, then rename over the original — KeePass's file transactions
  /// (§4.3). Either the original or the complete new file survives a crash.
  @override
  Future<void> write(List<int> bytes) async {
    if (!await Directory(location.handle).exists()) {
      throw DocumentLocationUnavailable(location);
    }

    await _sweepStaleTemps();
    final temp = File(p.join(location.handle, '$documentTempPrefix$pid'));
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(_path);
    } on FileSystemException {
      // §4.3 records that atomic rename is genuinely contentious here: a
      // cloud client holding the target open makes the replace fail, and
      // users hit this on Google Drive and GVfs mounts. Falling back to an
      // in-place write is the escape hatch that section asks for. It is safe
      // to take because the caller has already snapshotted the previous
      // bytes — see DocumentBackup.
      try {
        await File(_path).writeAsBytes(bytes, flush: true);
      } on FileSystemException catch (e2) {
        throw DocumentLocationUnavailable(location, e2);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    }
  }

  /// Removes temp files a crashed earlier run left behind.
  ///
  /// They sit in a folder the user is looking at and a sync client is
  /// uploading, so leaving them is not harmless clutter. Only names carrying
  /// our own prefix are touched, and only once they are old enough that no
  /// live save could still be holding them — a real write finishes in
  /// milliseconds, so anything this old was abandoned.
  Future<void> _sweepStaleTemps() async {
    final cutoff = DateTime.now().subtract(_staleTempAge);
    try {
      await for (final entity in Directory(
        location.handle,
      ).list(followLinks: false)) {
        if (entity is! File) continue;
        if (!p.basename(entity.path).startsWith(documentTempPrefix)) continue;
        if ((await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } on FileSystemException {
      // Housekeeping only. Never let it stop the save that follows.
    }
  }

  static const _staleTempAge = Duration(minutes: 5);
}
