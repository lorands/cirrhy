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

import 'dart:async';

import 'package:cirrhy/storage/document_directory.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';

/// Stands in for the OS folder picker.
///
/// Every real implementation of [DocumentDirectory] needs a running platform —
/// a GTK dialog, a SAF activity, a document picker — so the screen that drives
/// it is testable only against this.
final class FakeDocumentDirectory implements DocumentDirectory {
  FakeDocumentDirectory({
    this.picked,
    this.existing = const <String>[],
    this.available = true,
    this.failsToPick = false,
  });

  /// What the picker returns. Null means the user cancelled.
  DocumentLocation? picked;

  /// What [existingDocuments] finds — the adopt case when it is not empty.
  List<String> existing;

  bool available;
  bool failsToPick;

  int pickCount = 0;

  @override
  Future<DocumentLocation?> pick() async {
    pickCount++;
    if (failsToPick) throw const DocumentLocationUnavailable(_nowhere);
    return picked;
  }

  @override
  Future<bool> isAvailable(DocumentLocation location) async => available;

  @override
  Future<List<String>> existingDocuments(DocumentLocation location) async =>
      existing;

  /// Answers from [existing] plus whatever has actually been written, so the
  /// backup's find-a-free-name loop behaves against this fake the way it does
  /// against a real folder: the name it just wrote is taken on the next ask.
  @override
  Future<List<String>> existingFiles(
    DocumentLocation location,
    List<String> names,
  ) async => [
    for (final name in names)
      if (existing.contains(name) ||
          stores[_key(location, name)]?.bytes != null)
        name,
  ];

  /// Stands in for the platform's folder watcher — the `NSFilePresenter` on
  /// the two Apple platforms, nothing at all on the other three.
  final _changes = StreamController<void>.broadcast();

  /// Which locations [watch] has been asked about, in order.
  final List<DocumentLocation> watched = [];

  /// How many watch subscriptions are live right now, so a test can hold the
  /// session to letting go of the folder it no longer uses.
  int liveWatchers = 0;

  /// Fires the folder-changed signal at every live watcher, exactly as a sync
  /// client dropping a new file would.
  void announceChange() => _changes.add(null);

  @override
  Stream<void> watch(DocumentLocation location) {
    watched.add(location);
    late StreamController<void> out;
    StreamSubscription<void>? source;
    out = StreamController<void>(
      onListen: () {
        liveWatchers++;
        source = _changes.stream.listen(out.add);
      },
      onCancel: () async {
        liveWatchers--;
        await source?.cancel();
      },
    );
    return out.stream;
  }

  /// One in-memory store per handle and file name, shared across calls, so a
  /// "second device" is just a second repository over the same location.
  final Map<String, MemoryDocumentStore> stores = {};

  @override
  MemoryDocumentStore storeAt(
    DocumentLocation location, {
    String fileName = documentFileName,
  }) => stores.putIfAbsent(
    _key(location, fileName),
    () => MemoryDocumentStore(location),
  );

  static String _key(DocumentLocation location, String fileName) =>
      '${location.handle}::$fileName';

  static const _nowhere = DocumentLocation(handle: '?', label: '?');
}

/// A [DocumentStore] over a byte buffer, for tests that need storage without
/// a filesystem — its futures settle on the microtask queue, so it works
/// inside `testWidgets`' fake-async zone where real file IO would hang.
final class MemoryDocumentStore implements DocumentStore {
  MemoryDocumentStore(this.location);

  final DocumentLocation location;

  /// Null means the file does not exist yet.
  List<int>? bytes;

  /// When true, reads and writes throw [DocumentLocationUnavailable] — the
  /// revoked-permission / stale-bookmark case of §4.4.
  bool unavailable = false;

  int reads = 0;
  int writes = 0;

  @override
  Future<StoredBytes> read() async {
    if (unavailable) throw DocumentLocationUnavailable(location);
    reads++;
    final current = bytes;
    return current == null ? StoredBytes.empty : StoredBytes.of(current);
  }

  @override
  Future<void> write(List<int> data) async {
    if (unavailable) throw DocumentLocationUnavailable(location);
    writes++;
    bytes = List.of(data);
  }
}
