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

import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/services.dart';

import 'document_directory.dart';
import 'document_location.dart';

/// Android, iOS and macOS, where the OS hands back something that is not a
/// path and has to be kept.
///
/// A persisted SAF tree permission on Android, a security-scoped bookmark on
/// the two Apple platforms (DESIGN.md §4.1). No published package returns
/// either — pickers hand back a URI or a path and drop the durable grant — so
/// this is our own channel rather than a dependency.
///
/// The native side is deliberately dumb: it picks, checks, lists, reads and
/// writes bytes. Merging, hashing and every decision about what those bytes
/// mean stay in Dart, where they are tested headless.
final class ChannelDocumentDirectory implements DocumentDirectory {
  const ChannelDocumentDirectory();

  /// Matches the identity in DESIGN.md §7. Named for documents rather than
  /// files because what crosses it is a folder grant, not a file descriptor.
  static const channel = MethodChannel('com.lorands.cirrhy/documents');

  /// The code the native side raises when a handle no longer resolves.
  static const unavailableCode = 'unavailable';

  @override
  Future<DocumentLocation?> pick() async {
    final result = await channel.invokeMapMethod<String, Object?>(
      'pickDirectory',
    );
    if (result == null) return null; // The user cancelled.
    final handle = result['handle'];
    final label = result['label'];
    if (handle is! String || label is! String) return null;
    return DocumentLocation(handle: handle, label: label);
  }

  @override
  Future<bool> isAvailable(DocumentLocation location) async {
    try {
      final ok = await channel.invokeMethod<bool>('isAvailable', {
        'handle': location.handle,
      });
      return ok ?? false;
    } on PlatformException {
      // This method answers a question; it does not raise. A handle that
      // cannot even be queried is not available, which is the same answer.
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<List<String>> existingDocuments(DocumentLocation location) =>
      existingFiles(location, knownDocumentFileNames);

  @override
  Future<List<String>> existingFiles(
    DocumentLocation location,
    List<String> names,
  ) async {
    try {
      final found = await channel.invokeListMethod<String>('listDocuments', {
        'handle': location.handle,
        'names': names,
      });
      return found ?? const <String>[];
    } on PlatformException catch (e) {
      throw _translate(e, location);
    }
  }

  @override
  DocumentStore storeAt(
    DocumentLocation location, {
    String fileName = documentFileName,
  }) => ChannelDocumentStore(location, fileName: fileName);
}

/// Reads and writes one document through the platform channel.
final class ChannelDocumentStore implements DocumentStore {
  const ChannelDocumentStore(this.location, {this.fileName = documentFileName});

  final DocumentLocation location;
  final String fileName;

  @override
  Future<StoredBytes> read() async {
    try {
      final bytes = await ChannelDocumentDirectory.channel
          .invokeMethod<Uint8List>('readDocument', {
            'handle': location.handle,
            'name': fileName,
          });
      // Null is "the folder is fine, the document is not there yet" — the
      // ordinary first run. A missing *folder* comes back as an error instead,
      // because treating that as an empty document would overwrite the user's
      // history on the next save.
      return bytes == null ? StoredBytes.empty : StoredBytes.of(bytes);
    } on PlatformException catch (e) {
      throw _translate(e, location);
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    try {
      await ChannelDocumentDirectory.channel.invokeMethod<void>(
        'writeDocument',
        {
          'handle': location.handle,
          'name': fileName,
          // Uint8List crosses the channel as a byte array rather than a list
          // of boxed integers, which is the difference between one memcpy and
          // one message per byte.
          'bytes': Uint8List.fromList(bytes),
        },
      );
    } on PlatformException catch (e) {
      throw _translate(e, location);
    }
  }
}

Object _translate(PlatformException e, DocumentLocation location) =>
    e.code == ChannelDocumentDirectory.unavailableCode
    ? DocumentLocationUnavailable(location, e.message)
    : e;
