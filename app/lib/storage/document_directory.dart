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

import 'dart:io' show Platform;

import 'package:cirrhy_merge/cirrhy_merge.dart';

import 'channel_document_directory.dart';
import 'document_location.dart';
import 'path_document_directory.dart';

/// The platform surface for picking a folder and working inside it.
///
/// DESIGN.md §4.1 keeps this narrow deliberately: everything above it is plain
/// Dart, everything below it is per-platform work. The engine's
/// [DocumentStore] is narrower still — read and write — so this interface
/// exists for the three things the engine has no business knowing about:
/// asking the user, checking the handle still works, and looking inside the
/// folder before committing to it.
abstract interface class DocumentDirectory {
  /// Opens the platform's folder picker. Null when the user cancels.
  ///
  /// On the platforms that need it this also takes durable access — a
  /// persistable URI permission on Android, a security-scoped bookmark on
  /// macOS and iOS — so the returned handle survives a restart.
  Future<DocumentLocation?> pick();

  /// Whether [location] can still be reached.
  ///
  /// §4.4: iOS bookmarks go stale when the file moves or the provider app is
  /// reinstalled, and Android's persisted permissions can be revoked. Both
  /// have to degrade to a clear "choose your folder again", never a crash and
  /// never a silent start-from-empty, which would overwrite the user's history
  /// on the next save.
  Future<bool> isAvailable(DocumentLocation location);

  /// Which known document names already exist in [location].
  ///
  /// This is the adopt rule of §4.6: a folder that already holds a Cirrhy
  /// document is opened and merged rather than written over, which makes
  /// setting up the second device the same three taps as the first.
  Future<List<String>> existingDocuments(DocumentLocation location);

  /// Which of [names] already exist in [location].
  ///
  /// The general form behind [existingDocuments], asked by name rather than
  /// by listing the folder — a SAF directory listing is expensive, and the
  /// callers only ever have a yes/no question about names they already know.
  /// The manual backup (§11) uses it to find a free dated name instead of
  /// overwriting a copy the user deliberately took.
  Future<List<String>> existingFiles(
    DocumentLocation location,
    List<String> names,
  );

  /// Fires whenever something that is not this app changes what is inside
  /// [location] — which is exactly what a sync client delivering another
  /// device's write looks like from here.
  ///
  /// **Additive, never a replacement for asking.** §4.4 lists "no change
  /// notification" as an accepted failure mode and that stays true: the
  /// platforms with nothing to offer return an empty stream, and even where
  /// the signal exists a cloud provider decides for itself whether and when to
  /// send it. `SessionRefresher`'s schedule is what makes the document
  /// current; this only makes it current *sooner*, and where it works it turns
  /// "up to a minute late" into "as it lands".
  ///
  /// The subscription owns the platform-side observation: cancelling it stops
  /// the watching, and a second subscription is a second observer. A stream
  /// that errors or ends is the platform saying it cannot watch — a fact about
  /// the platform, never a failure the user should be told about.
  Stream<void> watch(DocumentLocation location);

  /// A store bound to [location], to hand to a `DocumentRepository`.
  ///
  /// [fileName] exists for the manual backup (§11), which writes its dated
  /// sibling copy through the same store the document uses — same channel,
  /// same failure modes, same [DocumentLocationUnavailable]. Nothing else
  /// passes it: the document's own name is fixed and never asked (§4.6).
  DocumentStore storeAt(
    DocumentLocation location, {
    String fileName = documentFileName,
  });

  /// The implementation for the platform this build is running on.
  ///
  /// Linux and Windows get a plain path and need no native code at all. The
  /// other three go through a method channel, because each needs the OS to
  /// hand back something durable that a path is not.
  factory DocumentDirectory.forPlatform() {
    if (Platform.isLinux || Platform.isWindows) {
      return const PathDocumentDirectory();
    }
    return const ChannelDocumentDirectory();
  }
}

/// The folder is gone, or access to it was revoked.
///
/// Thrown by reads and writes rather than by [DocumentDirectory.isAvailable],
/// which answers the same question without raising. Callers must treat this as
/// "send the user back to the picker" (§4.4).
final class DocumentLocationUnavailable implements Exception {
  const DocumentLocationUnavailable(this.location, [this.cause]);

  final DocumentLocation location;
  final Object? cause;

  @override
  String toString() =>
      'DocumentLocationUnavailable: cannot reach $location'
      '${cause == null ? '' : ': $cause'}';
}
