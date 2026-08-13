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

import 'package:flutter/foundation.dart';

/// The folder the user chose, as the platform describes it.
///
/// DESIGN.md §4.2: Cirrhy asks for a directory, never a single document. A
/// document-scoped handle grants access to that document and nothing around
/// it, which rules out writing a sibling temp file and renaming over the
/// original — so every save would degrade to an in-place overwrite of the file
/// holding all of the user's data.
@immutable
final class DocumentLocation {
  const DocumentLocation({required this.handle, required this.label});

  /// What the platform gave us, and **opaque on purpose**.
  ///
  /// A filesystem path on Linux and Windows, a base64 security-scoped bookmark
  /// on macOS and iOS, a SAF tree URI on Android (§4.1). Nothing outside the
  /// platform implementation may parse it, join onto it, or show it to anyone.
  final String handle;

  /// What to show the user, because [handle] cannot be shown.
  ///
  /// A bookmark is a binary blob and a SAF URI is `content://…/tree/primary%3A…`.
  /// Both are useless on screen, so the platform supplies a display name at
  /// pick time and it is stored alongside. On desktop this is just the path,
  /// which is genuinely the most useful thing to show there.
  final String label;

  Map<String, Object?> toJson() => {'handle': handle, 'label': label};

  /// Null rather than throwing when the stored value is unusable.
  ///
  /// A preference written by another build, or half-written, must degrade to
  /// "nothing chosen yet" and send the user back to the picker. Failing to
  /// start is not an option for a setting this early in the app's life.
  static DocumentLocation? tryParse(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return null;
      final handle = decoded['handle'];
      final label = decoded['label'];
      if (handle is! String || handle.isEmpty || label is! String) return null;
      return DocumentLocation(handle: handle, label: label);
    } on FormatException {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is DocumentLocation &&
      other.handle == handle &&
      other.label == label;

  @override
  int get hashCode => Object.hash(handle, label);

  // The handle is deliberately absent: this ends up in logs and error text,
  // and a bookmark blob helps nobody read them.
  @override
  String toString() => 'DocumentLocation($label)';
}

/// The document's name inside the chosen folder.
///
/// Fixed, not asked. One user, one document (§1), so a name field would buy
/// nothing — and it would break the adopt rule in §4.6, which recognises the
/// document already sitting in a synced folder by knowing what it is called.
const String documentFileName = 'cirrhy.json';

/// The names the adopt rule recognises.
///
/// A list rather than the single constant because DESIGN.md §5 has not settled
/// JSON versus CBOR. If that lands on CBOR, the file this app creates changes
/// name and this is the one place that has to learn about both.
const List<String> knownDocumentFileNames = <String>[documentFileName];

/// Prefix for the temp file used by the write-then-rename save (§4.3).
///
/// Distinctive because it is created inside a folder the user is watching and
/// a sync client is uploading. Anything matching it is ours and can be swept.
const String documentTempPrefix = '$documentFileName.tmp-';
