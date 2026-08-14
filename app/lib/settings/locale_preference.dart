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

// widgets.dart, not foundation.dart: Locale comes from dart:ui and is
// re-exported here. This file still pulls in no widget of its own.
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's chosen UI language, or null to follow the operating system.
///
/// Null is the default and the normal state. Cirrhy only overrides the system
/// language when the user explicitly asks it to, and "back to system" is
/// always reachable — that is why this is a nullable [Locale] rather than a
/// language code with a magic "system" sentinel.
///
/// **This is deliberately not stored in the Cirrhy document.** DESIGN.md §3.6
/// establishes that device-scoped state must not go through last-write-wins
/// merge, using the running timer as the case. A language is the same shape: a
/// Hungarian phone and an English work laptop are both legitimate, and putting
/// the choice in the synced file would flip one device's UI because the other
/// changed it. It lives in platform preferences instead, which also keeps the
/// single-file promise about *tracking data* honest.
class LocalePreference extends ChangeNotifier {
  LocalePreference._(this._prefs, this._locale);

  static const _key = 'settings.locale';

  final SharedPreferences _prefs;
  Locale? _locale;

  /// Reads the stored choice. Returns a preference that follows the system
  /// when nothing has been chosen, or when what was stored is no longer a
  /// language the app ships — dropping a translation must not strand a user
  /// in a language that no longer exists.
  static Future<LocalePreference> load(Iterable<Locale> supported) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    final known = supported.any((l) => l.languageCode == stored);
    return LocalePreference._(prefs, known ? Locale(stored!) : null);
  }

  /// The override, or null when following the system.
  Locale? get locale => _locale;

  /// Whether the app is following the operating system's language.
  bool get followsSystem => _locale == null;

  /// Sets the override, or clears it with null to go back to the system.
  Future<void> set(Locale? locale) async {
    if (_locale?.languageCode == locale?.languageCode) return;
    _locale = locale;
    notifyListeners();
    if (locale == null) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(_key, locale.languageCode);
    }
  }
}
