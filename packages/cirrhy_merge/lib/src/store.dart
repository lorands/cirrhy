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

import 'codec.dart';
import 'document.dart';
import 'merge.dart';

/// Bytes as read, with the hash they hashed to.
final class StoredBytes {
  const StoredBytes(this.bytes, this.hash);

  StoredBytes.of(List<int> bytes) : this(bytes, contentHash(bytes));

  final List<int> bytes;
  final String hash;

  static final empty = StoredBytes.of(const []);
}

/// The entire platform surface, per DESIGN.md §4.1.
///
/// Everything above this line is plain Dart. Everything below it is
/// platform-channel work — security-scoped bookmarks on iOS, persistable URI
/// permissions on Android, a path everywhere else. **Cirrhy contains no network
/// or cloud-provider code**; sync is the user's business (§4).
abstract interface class DocumentStore {
  /// Reads the current bytes. Returns [StoredBytes.empty] when the file does
  /// not exist yet.
  Future<StoredBytes> read();

  /// Writes [bytes], atomically where the platform allows (§4.3).
  Future<void> write(List<int> bytes);
}

/// Raised when the file on disk cannot be parsed during a save.
///
/// Saving deliberately fails closed here. Treating an unparseable file as empty
/// and merging into it would write the user's entire history away.
final class SaveBlockedException implements Exception {
  const SaveBlockedException(this.cause);
  final Object cause;
  @override
  String toString() =>
      'SaveBlockedException: refused to overwrite an unreadable file: $cause';
}

/// Read-merge-write against whatever is currently on disk.
///
/// DESIGN.md §3.2: every save re-reads the file, merges, and writes the result.
/// Never a blind overwrite. Where KeePass *prompts* on detecting a changed
/// file, Cirrhy merges automatically — a single user with no team has nobody to
/// arbitrate with, and a prompt they cannot meaningfully answer is worse than a
/// correct default.
final class DocumentRepository {
  DocumentRepository({
    required DocumentStore store,
    DocumentCodec codec = const JsonDocumentCodec(),
    int historyLimit = defaultHistoryLimit,
  }) : _store = store,
       _codec = codec,
       _historyLimit = historyLimit;

  final DocumentStore _store;
  final DocumentCodec _codec;
  final int _historyLimit;

  /// Hash of the bytes this process last read or wrote.
  String? _knownHash;

  String? get knownHash => _knownHash;

  Future<CirrhyDocument> load() async {
    final stored = await _store.read();
    _knownHash = stored.hash;
    return _codec.decode(stored.bytes);
  }

  /// Merges [document] into what is on disk and writes the result back.
  ///
  /// Returns the merged document — the caller must adopt it, since it may
  /// contain records this device has never seen.
  Future<CirrhyDocument> save(CirrhyDocument document) async {
    final stored = await _store.read();

    // The common case: nothing else touched the file, so there is nothing to
    // merge. Still a full re-read, because nothing notifies us of changes
    // (§4.4) and mtime is not trustworthy (§3.2).
    if (stored.hash == _knownHash) {
      return _write(document);
    }

    final CirrhyDocument onDisk;
    try {
      onDisk = _codec.decode(stored.bytes);
    } on DocumentFormatException catch (e) {
      throw SaveBlockedException(e);
    }

    return _write(
      mergeDocuments(onDisk, document, historyLimit: _historyLimit),
    );
  }

  /// Re-reads and merges without writing.
  ///
  /// Call on every foreground/resume: nothing tells us the file changed
  /// underneath us, so the app has to ask (§4.4).
  Future<CirrhyDocument> refresh(CirrhyDocument document) async {
    final stored = await _store.read();
    if (stored.hash == _knownHash) return document;

    final onDisk = _codec.decode(stored.bytes);
    _knownHash = stored.hash;
    return mergeDocuments(onDisk, document, historyLimit: _historyLimit);
  }

  Future<CirrhyDocument> _write(CirrhyDocument document) async {
    final bytes = _codec.encode(document);
    await _store.write(bytes);
    _knownHash = contentHash(bytes);
    return document;
  }
}
