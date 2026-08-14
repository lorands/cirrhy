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

import 'package:cirrhy/main.dart';
import 'package:cirrhy/settings/theme_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ThemePreference', () {
    test('follows the system when nothing has been chosen', () async {
      final pref = await ThemePreference.load();
      expect(pref.mode, ThemeMode.system);
    });

    test('a choice survives a restart', () async {
      final first = await ThemePreference.load();
      await first.set(ThemeMode.dark);

      final reloaded = await ThemePreference.load();
      expect(reloaded.mode, ThemeMode.dark);
    });

    test('going back to system persists too', () async {
      final pref = await ThemePreference.load();
      await pref.set(ThemeMode.light);
      await pref.set(ThemeMode.system);

      expect(pref.mode, ThemeMode.system);
      expect((await ThemePreference.load()).mode, ThemeMode.system);
    });

    test('a stored value this build does not recognise falls back to '
        'system', () async {
      // Mirrors LocalePreference's handling of a dropped language: an
      // unrecognised value must not strand the app on a mode it cannot
      // otherwise reach, so it lands on the safe default instead.
      SharedPreferences.setMockInitialValues({'settings.themeMode': 'sepia'});
      final pref = await ThemePreference.load();
      expect(pref.mode, ThemeMode.system);
    });

    test('notifies listeners so the UI can rebuild', () async {
      final pref = await ThemePreference.load();
      var notifications = 0;
      pref.addListener(() => notifications++);

      await pref.set(ThemeMode.dark);
      expect(notifications, 1);

      // Setting the same mode again is not a change.
      await pref.set(ThemeMode.dark);
      expect(notifications, 1);

      await pref.set(ThemeMode.system);
      expect(notifications, 2);
    });
  });

  group('the app honours the choice', () {
    testWidgets('picking Dark flips MaterialApp.themeMode live', (
      tester,
    ) async {
      final pref = await ThemePreference.load();

      await tester.pumpWidget(CirrhyApp(themePreference: pref));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );

      await pref.set(ThemeMode.dark);
      await tester.pumpAndSettle();

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
    });

    testWidgets('a null preference leaves the app on system, as before', (
      tester,
    ) async {
      await tester.pumpWidget(const CirrhyApp());
      await tester.pumpAndSettle();

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
    });
  });
}
