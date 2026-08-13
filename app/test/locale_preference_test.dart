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

import 'package:cirrhy/l10n/generated/app_localizations.dart';
import 'package:cirrhy/main.dart';
import 'package:cirrhy/settings/document_location_preference.dart';
import 'package:cirrhy/settings/locale_preference.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_document_directory.dart';

const supported = AppLocalizations.supportedLocales;

/// Opens the app and navigates to preferences, where the language picker
/// lives.
///
/// It moved there off the placeholder screen when the preferences screen was
/// built (DESIGN.md §4.6); the [LocalePreference] behind it did not change.
/// The folder is pre-chosen so the app does not open on first run.
Future<void> pumpAppAtPreferences(
  WidgetTester tester,
  LocalePreference locale,
) async {
  final location = await DocumentLocationPreference.load();
  await location.set(
    const DocumentLocation(handle: '/tmp/cirrhy', label: '/tmp/cirrhy'),
  );

  await tester.pumpWidget(
    CirrhyApp(
      localePreference: locale,
      locationPreference: location,
      directory: FakeDocumentDirectory(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LocalePreference', () {
    test('follows the system when nothing has been chosen', () async {
      final pref = await LocalePreference.load(supported);
      expect(pref.locale, isNull);
      expect(pref.followsSystem, isTrue);
    });

    test('a choice survives a restart', () async {
      final first = await LocalePreference.load(supported);
      await first.set(const Locale('hu'));

      final reloaded = await LocalePreference.load(supported);
      expect(reloaded.locale, const Locale('hu'));
      expect(reloaded.followsSystem, isFalse);
    });

    test('clearing the choice goes back to the system', () async {
      final pref = await LocalePreference.load(supported);
      await pref.set(const Locale('de'));
      await pref.set(null);

      expect(pref.followsSystem, isTrue);
      expect((await LocalePreference.load(supported)).locale, isNull);
    });

    test('a stored language the app no longer ships is ignored', () async {
      // Dropping a translation must not strand someone in a language that has
      // no strings left, so an unknown code falls back to following the system
      // rather than being handed to MaterialApp.
      SharedPreferences.setMockInitialValues({'settings.locale': 'fr'});
      final pref = await LocalePreference.load(supported);
      expect(pref.locale, isNull);
    });

    test('notifies listeners so the UI can rebuild', () async {
      final pref = await LocalePreference.load(supported);
      var notifications = 0;
      pref.addListener(() => notifications++);

      await pref.set(const Locale('es'));
      expect(notifications, 1);

      // Setting the same language again is not a change.
      await pref.set(const Locale('es'));
      expect(notifications, 1);

      await pref.set(null);
      expect(notifications, 2);
    });
  });

  group('the app honours the choice', () {
    testWidgets('an override beats the system language', (tester) async {
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.binding.platformDispatcher.localesTestValue = [const Locale('de')];

      final pref = await LocalePreference.load(supported);
      await pref.set(const Locale('hu'));

      await tester.pumpWidget(CirrhyApp(localePreference: pref));
      await tester.pumpAndSettle();

      expect(
        find.text('Még nincs felület — előbb az összefésülő motor készül el.'),
        findsOneWidget,
      );
    });

    testWidgets('no override means the system language', (tester) async {
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.binding.platformDispatcher.localesTestValue = [const Locale('it')];

      final pref = await LocalePreference.load(supported);

      await tester.pumpWidget(CirrhyApp(localePreference: pref));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Nessuna interfaccia per ora: prima viene il motore di unione.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('switching redraws immediately, without a restart', (
      tester,
    ) async {
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];

      final pref = await LocalePreference.load(supported);
      await tester.pumpWidget(CirrhyApp(localePreference: pref));
      await tester.pumpAndSettle();
      expect(
        find.text('No UI yet — the merge engine comes first.'),
        findsOneWidget,
      );

      await pref.set(const Locale('es'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Todavía no hay interfaz: primero se construye el motor de fusión.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the picker lists every language in its own name', (
      tester,
    ) async {
      final pref = await LocalePreference.load(supported);
      await pumpAppAtPreferences(tester, pref);

      await tester.tap(find.byType(DropdownMenu<Locale?>));
      await tester.pumpAndSettle();

      for (final name in [
        'Magyar',
        'English',
        'Español',
        'Italiano',
        'Deutsch',
      ]) {
        expect(
          find.text(name),
          findsWidgets,
          reason: '$name missing from picker',
        );
      }
    });

    testWidgets('picking a language from the menu applies it', (tester) async {
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];

      final pref = await LocalePreference.load(supported);
      await pumpAppAtPreferences(tester, pref);

      await tester.tap(find.byType(DropdownMenu<Locale?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Magyar').last);
      await tester.pumpAndSettle();

      expect(pref.locale, const Locale('hu'));
      // The preferences screen itself is now in Hungarian, which is the same
      // property the placeholder used to demonstrate: the switch redraws the
      // whole app, not just the screen that owns the picker.
      expect(find.text('Beállítások'), findsOneWidget);
    });
  });
}
