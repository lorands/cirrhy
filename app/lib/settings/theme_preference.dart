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

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's chosen light/dark override, or [ThemeMode.system] to follow
/// the operating system.
///
/// [ThemeMode.system] is the default and the normal state — the same shape
/// as [LocalePreference]'s null-means-system, just spelled with the enum's
/// own sentinel instead of layering one on top of a narrower type.
///
/// **This is deliberately not stored in the Cirrhy document.** DESIGN.md
/// §3.7 keeps device-scoped state out of last-write-wins merge, using the
/// running timer as the case; a theme override is the same shape as the
/// language override right next to it in preferences — a work laptop kept in
/// light mode and a phone kept in dark mode are both legitimate, and a
/// synced choice would flip one device's appearance because the other
/// changed it.
class ThemePreference extends ChangeNotifier {
  ThemePreference._(this._prefs, this._mode);

  static const _key = 'settings.themeMode';

  final SharedPreferences _prefs;
  ThemeMode _mode;

  static ThemeMode _decode(String? stored) => switch (stored) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    // Covers both "nothing stored yet" and a value this build no longer
    // recognises — either way, following the system is the safe default.
    _ => ThemeMode.system,
  };

  static String _encode(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  /// Reads the stored choice. Falls back to [ThemeMode.system] when nothing
  /// has been chosen, or when what was stored is not a value this build
  /// recognises.
  static Future<ThemePreference> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ThemePreference._(prefs, _decode(prefs.getString(_key)));
  }

  /// The active mode. Defaults to [ThemeMode.system].
  ThemeMode get mode => _mode;

  /// Sets the override. Pass [ThemeMode.system] to go back to following the
  /// operating system.
  Future<void> set(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await _prefs.setString(_key, _encode(mode));
  }
}
