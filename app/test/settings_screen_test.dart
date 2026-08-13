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
import 'package:cirrhy/settings/settings_screen.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_document_directory.dart';

const dropbox = DocumentLocation(
  handle: '/home/u/Dropbox/cirrhy',
  label: '/home/u/Dropbox/cirrhy',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(LocalePreference, DocumentLocationPreference)> prefs() async => (
    await LocalePreference.load(AppLocalizations.supportedLocales),
    await DocumentLocationPreference.load(),
  );

  Future<void> pumpSettings(
    WidgetTester tester, {
    required FakeDocumentDirectory directory,
    required DocumentLocationPreference location,
    required LocalePreference locale,
    bool firstRun = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // The real theme, because the screen reads CirrhyTheme off it.
        theme: cirrhyLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: ListenableBuilder(
          listenable: location,
          builder: (context, _) => SettingsScreen(
            localePreference: locale,
            locationPreference: location,
            directory: directory,
            firstRun: firstRun,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('first run', () {
    testWidgets('asks for a folder before anything else', (tester) async {
      final (locale, location) = await prefs();
      await pumpSettings(
        tester,
        directory: FakeDocumentDirectory(),
        location: location,
        locale: locale,
        firstRun: true,
      );

      expect(find.text('Welcome to Cirrhy'), findsOneWidget);
      expect(find.text('No folder chosen yet'), findsOneWidget);
      expect(find.text('Choose folder…'), findsOneWidget);
    });

    testWidgets('cannot be left until a folder is chosen', (tester) async {
      // The file is the app's entire state, so there is nothing to show
      // before it exists. DESIGN.md §4.6 gates rather than defaulting.
      final (locale, location) = await prefs();
      await pumpSettings(
        tester,
        directory: FakeDocumentDirectory(picked: dropbox),
        location: location,
        locale: locale,
        firstRun: true,
      );

      final button = find.widgetWithText(FilledButton, 'Continue');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.tap(find.text('Choose folder…'));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });

    testWidgets('stays put after picking, so the note can be read', (
      tester,
    ) async {
      final (locale, location) = await prefs();
      await pumpSettings(
        tester,
        directory: FakeDocumentDirectory(picked: dropbox),
        location: location,
        locale: locale,
        firstRun: true,
      );

      await tester.tap(find.text('Choose folder…'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Cirrhy'), findsOneWidget);
    });
  });

  group('choosing a folder', () {
    testWidgets('an empty folder says the file will be created', (
      tester,
    ) async {
      final (locale, location) = await prefs();
      await pumpSettings(
        tester,
        directory: FakeDocumentDirectory(picked: dropbox),
        location: location,
        locale: locale,
      );

      await tester.tap(find.text('Choose folder…'));
      await tester.pumpAndSettle();

      expect(
        find.text('Cirrhy will create its file in this folder.'),
        findsOneWidget,
      );
      expect(location.location, dropbox);
      expect(find.text('/home/u/Dropbox/cirrhy'), findsOneWidget);
    });

    // The adopt rule of §4.6, and the case every device after the first hits.
    // "Merged" is the word that matters: read-merge-write means pointing a
    // second device at the folder joins the history rather than replacing it.
    testWidgets('a folder that already has a document says it will merge', (
      tester,
    ) async {
      final (locale, location) = await prefs();
      await pumpSettings(
        tester,
        directory: FakeDocumentDirectory(
          picked: dropbox,
          existing: const ['cirrhy.json'],
        ),
        location: location,
        locale: locale,
      );

      await tester.tap(find.text('Choose folder…'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This folder already has a Cirrhy file. Your data will be merged '
          'with it.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('cancelling changes nothing', (tester) async {
      final (locale, location) = await prefs();
      await pumpSettings(
        tester,
        directory: FakeDocumentDirectory(),
        location: location,
        locale: locale,
      );

      await tester.tap(find.text('Choose folder…'));
      await tester.pumpAndSettle();

      expect(location.isChosen, isFalse);
      expect(find.text('No folder chosen yet'), findsOneWidget);
    });

    testWidgets('a picker that fails says so without blaming the user', (
      tester,
    ) async {
      final (locale, location) = await prefs();
      await pumpSettings(
        tester,
        directory: FakeDocumentDirectory(failsToPick: true),
        location: location,
        locale: locale,
      );

      await tester.tap(find.text('Choose folder…'));
      await tester.pumpAndSettle();

      expect(find.text('That folder could not be opened.'), findsOneWidget);
      expect(location.isChosen, isFalse);
    });

    testWidgets('relocating replaces the folder shown', (tester) async {
      final (locale, location) = await prefs();
      await location.set(dropbox);
      const moved = DocumentLocation(handle: '/mnt/sync', label: '/mnt/sync');
      await pumpSettings(
        tester,
        directory: FakeDocumentDirectory(picked: moved),
        location: location,
        locale: locale,
      );

      // Already chosen, so the button offers a change rather than a first pick.
      await tester.tap(find.text('Change folder…'));
      await tester.pumpAndSettle();

      expect(find.text('/mnt/sync'), findsOneWidget);
      expect(find.text('/home/u/Dropbox/cirrhy'), findsNothing);
    });
  });

  // §4.4: bookmarks go stale, permissions get revoked. Never a crash, and
  // never a silent start-from-empty that the next save would write out.
  testWidgets('a folder that can no longer be reached says so', (tester) async {
    final (locale, location) = await prefs();
    await location.set(dropbox);
    await pumpSettings(
      tester,
      directory: FakeDocumentDirectory(available: false),
      location: location,
      locale: locale,
    );

    expect(
      find.text('Cirrhy cannot reach this folder any more. Choose it again.'),
      findsOneWidget,
    );
  });

  group('routing', () {
    testWidgets('the app opens on first run when no folder is chosen', (
      tester,
    ) async {
      final (locale, location) = await prefs();
      await tester.pumpWidget(
        CirrhyApp(
          localePreference: locale,
          locationPreference: location,
          directory: FakeDocumentDirectory(picked: dropbox),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Cirrhy'), findsOneWidget);
    });

    testWidgets('and goes straight past it once one is', (tester) async {
      final (locale, location) = await prefs();
      await location.set(dropbox);
      await tester.pumpWidget(
        CirrhyApp(
          localePreference: locale,
          locationPreference: location,
          directory: FakeDocumentDirectory(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Cirrhy'), findsNothing);
      expect(
        find.text('No UI yet — the merge engine comes first.'),
        findsOneWidget,
      );
    });

    testWidgets('continuing from first run reaches the app', (tester) async {
      final (locale, location) = await prefs();
      await tester.pumpWidget(
        CirrhyApp(
          localePreference: locale,
          locationPreference: location,
          directory: FakeDocumentDirectory(picked: dropbox),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose folder…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(
        find.text('No UI yet — the merge engine comes first.'),
        findsOneWidget,
      );
    });

    testWidgets('preferences are reachable from the app', (tester) async {
      final (locale, location) = await prefs();
      await location.set(dropbox);
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

      expect(find.text('Preferences'), findsOneWidget);
      expect(find.text('Data folder'), findsOneWidget);
      // The language picker moved here off the placeholder screen.
      expect(find.byType(DropdownMenu<Locale?>), findsOneWidget);
    });
  });
}
