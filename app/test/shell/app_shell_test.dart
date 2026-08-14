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
import 'package:cirrhy/reports/range_format.dart';
import 'package:cirrhy/reports/report_query.dart';
import 'package:cirrhy/settings/document_location_preference.dart';
import 'package:cirrhy/settings/locale_preference.dart';
import 'package:cirrhy/shell/app_shell.dart';
import 'package:cirrhy/shell/watermark.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_document_directory.dart';

Future<void> pumpShell(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  LocalePreference? localePreference,
  DocumentLocationPreference? locationPreference,
  FakeDocumentDirectory? directory,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // The real theme, because the shell reads CirrhyTheme off it.
      theme: cirrhyLightTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: AppShell(
        localePreference: localePreference,
        locationPreference: locationPreference,
        directory: directory,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(LocalePreference, DocumentLocationPreference)> prefs() async => (
    await LocalePreference.load(AppLocalizations.supportedLocales),
    await DocumentLocationPreference.load(),
  );

  group('destinations', () {
    testWidgets('all four tabs switch and show their own content', (
      tester,
    ) async {
      final (locale, location) = await prefs();
      await location.set(
        const DocumentLocation(handle: '/tmp/cirrhy', label: '/tmp/cirrhy'),
      );
      await pumpShell(
        tester,
        localePreference: locale,
        locationPreference: location,
        directory: FakeDocumentDirectory(),
      );

      // Timer is selected by default.
      expect(find.text('What are you working on?'), findsOneWidget);

      // Each destination's caption is always in the bottom bar, and the
      // hidden destinations are skipped by the finders — so a *second* copy
      // of the label is what proves the screen behind it is the live one.
      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      expect(find.text('Reports'), findsNWidgets(2));

      await tester.tap(find.text('Projects'));
      await tester.pumpAndSettle();
      expect(find.text('Projects'), findsNWidgets(2));

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Data folder'), findsOneWidget);

      await tester.tap(find.text('Timer'));
      await tester.pumpAndSettle();
      expect(find.text('What are you working on?'), findsOneWidget);
    });

    testWidgets('an unconfigured shell still builds, with an empty Settings '
        'tab', (tester) async {
      // The const CirrhyApp() test constructor passes no dependencies at all.
      await pumpShell(tester);

      expect(find.text('What are you working on?'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // No crash, and nothing claiming to be the preferences screen.
      expect(find.text('Data folder'), findsNothing);
    });
  });

  group('destination state', () {
    testWidgets('every destination stays mounted, so switching away and back '
        'keeps what the user had set up', (tester) async {
      await pumpShell(tester);

      // All four are built at once — that is what makes the state survive.
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);

      await tester.tap(find.byKey(const Key('navTab1')));
      await tester.pumpAndSettle();
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);

      // Step the reports window back a week. en_US starts weeks on Sunday.
      await tester.tap(find.byKey(const Key('reportsPreviousRange')));
      await tester.pumpAndSettle();

      final previousWeek = addDays(startOfWeek(DateTime.now(), 0), -7);
      final expected = formatReportRange(
        ReportRange.week,
        previousWeek,
        addDays(previousWeek, 7),
        'en',
      );
      expect(find.text(expected), findsOneWidget);

      // Away to Projects and back: the stepped-back week is still there. A
      // rebuilt ReportsScreen would have snapped to the current week.
      await tester.tap(find.byKey(const Key('navTab2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('navTab1')));
      await tester.pumpAndSettle();

      expect(find.text(expected), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('a narrow surface uses the bottom bar, not the rail', (
      tester,
    ) async {
      await pumpShell(tester); // Default test surface is 800×600.

      // The rail's lockup is a second "Cirrhy", next to the Timer tab's own
      // header. A narrow layout has only the header's.
      expect(find.text('Cirrhy'), findsOneWidget);
      // The last destination sits far right in a full-width bottom bar; a
      // 220px-wide rail could not place it there.
      expect(tester.getTopLeft(find.byIcon(Icons.tune)).dx, greaterThan(220));
    });

    testWidgets('a wide surface uses the rail, not the bottom bar', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;

      await pumpShell(tester);

      expect(find.text('Cirrhy'), findsNWidgets(2));
      expect(tester.getTopLeft(find.byIcon(Icons.tune)).dx, lessThan(220));
    });
  });

  group('watermark', () {
    testWidgets('renders exactly once and ignores pointers', (tester) async {
      await pumpShell(tester);

      expect(find.byType(CirrhyWatermark), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CirrhyWatermark),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    });
  });

  group('l10n', () {
    testWidgets('tab labels come from the English delegate', (tester) async {
      await pumpShell(tester);

      for (final label in ['Timer', 'Reports', 'Projects', 'Settings']) {
        expect(find.text(label), findsOneWidget, reason: '$label missing');
      }
    });

    testWidgets('tab labels come from the Hungarian delegate', (tester) async {
      await pumpShell(tester, locale: const Locale('hu'));

      for (final label in [
        'Időmérő',
        'Jelentések',
        'Projektek',
        'Beállítások',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label missing');
      }
    });
  });
}
