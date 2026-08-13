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

  @override
  DocumentStore storeAt(DocumentLocation location) =>
      throw UnimplementedError('no test needs to read through the fake yet');

  static const _nowhere = DocumentLocation(handle: '?', label: '?');
}
