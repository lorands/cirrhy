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

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/document_location.dart';

/// Where this device keeps the Cirrhy document, or null if it has not been
/// asked yet.
///
/// **Device-scoped, and stored in platform preferences rather than the
/// document** — DESIGN.md §3.7 and §4.6. The argument here does not even need
/// last-write-wins to make it: an iOS security-scoped bookmark is meaningless
/// on Linux, and one user legitimately keeps the file at `~/Dropbox/cirrhy` on
/// the laptop and inside an iCloud folder on the phone. Those are not a
/// conflict to be resolved, they are two correct answers.
///
/// Null is the first-run state, and it is what the preferences screen shows in
/// its first-run presentation (§4.6). It is also where a revoked or stale
/// handle lands: a location that no longer resolves is cleared rather than
/// kept, because every screen downstream would otherwise have to carry a
/// "chosen but broken" case.
class DocumentLocationPreference extends ChangeNotifier {
  DocumentLocationPreference._(this._prefs, this._location);

  static const _key = 'settings.documentLocation';

  final SharedPreferences _prefs;
  DocumentLocation? _location;

  /// Reads the stored choice, without checking that it still resolves.
  ///
  /// Verifying costs a platform round trip — on iOS it means resolving a
  /// bookmark and starting a security-scoped access — so it belongs on the
  /// first read of the document, not in front of the first frame. [clear] is
  /// what that check calls when it finds the handle dead.
  static Future<DocumentLocationPreference> load() async {
    final prefs = await SharedPreferences.getInstance();
    return DocumentLocationPreference._(
      prefs,
      DocumentLocation.tryParse(prefs.getString(_key)),
    );
  }

  /// The chosen folder, or null when the user has not chosen one.
  DocumentLocation? get location => _location;

  /// Whether the app has somewhere to keep the document.
  bool get isChosen => _location != null;

  /// Records a newly picked folder.
  ///
  /// Only the preference moves. Getting the *document* to the new folder is a
  /// save away — read-merge-write (§3.2) merges into whatever is already
  /// there, which is what makes relocating safe and what makes pointing two
  /// devices at the same folder work.
  Future<void> set(DocumentLocation location) async {
    if (_location == location) return;
    _location = location;
    notifyListeners();
    await _prefs.setString(_key, location.encode());
  }

  /// Forgets the folder, sending the app back to the picker.
  ///
  /// For a handle that went stale or was revoked (§4.4). Note what this does
  /// *not* do: it never deletes anything in the folder. The document is the
  /// user's file in the user's sync folder, and a permission we lost is no
  /// reason to touch it.
  Future<void> clear() async {
    if (_location == null) return;
    _location = null;
    notifyListeners();
    await _prefs.remove(_key);
  }
}
