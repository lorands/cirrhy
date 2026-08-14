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

/// Guards against text that paints in no colour at all.
///
/// This is not hypothetical. The preferences screen shipped its section
/// headings in `titleSmall`, which the design system does not map, and
/// `ThemeData.copyWith` replaces the whole TextTheme rather than merging it —
/// so the role survived with its geometry and no colour, and painted white on
/// a white ground. Every test passed, because a colourless style still finds
/// its widget, still lays out, and still reads back the right characters. Only
/// a screenshot showed it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Every visible Text under [finder], with the style it will actually paint.
  List<(String, TextStyle)> painted(WidgetTester tester) {
    return [
      for (final element in find.byType(Text).evaluate())
        if ((element.widget as Text).data case final String data)
          (
            data,
            DefaultTextStyle.of(
              element,
            ).style.merge((element.widget as Text).style),
          ),
    ];
  }

  Future<void> pumpSettings(
    WidgetTester tester, {
    required ThemeData theme,
    required bool firstRun,
    required bool chosen,
  }) async {
    final locale = await LocalePreference.load(
      AppLocalizations.supportedLocales,
    );
    final location = await DocumentLocationPreference.load();
    if (chosen) {
      await location.set(
        const DocumentLocation(handle: '/tmp/sync', label: '/tmp/sync'),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: SettingsScreen(
          localePreference: locale,
          locationPreference: location,
          directory: FakeDocumentDirectory(),
          firstRun: firstRun,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (name, theme) in [
    ('light', cirrhyLightTheme()),
    ('dark', cirrhyDarkTheme()),
  ]) {
    for (final firstRun in [true, false]) {
      testWidgets(
        'every string on ${firstRun ? 'first run' : 'preferences'} has a '
        'colour in $name',
        (tester) async {
          await pumpSettings(
            tester,
            theme: theme,
            firstRun: firstRun,
            chosen: !firstRun,
          );

          for (final (text, style) in painted(tester)) {
            expect(
              style.color,
              isNotNull,
              reason:
                  '"$text" would paint in the renderer\'s default colour, '
                  'which is not a colour anybody chose',
            );
          }
        },
      );
    }
  }

  testWidgets('and on the screen behind it', (tester) async {
    final locale = await LocalePreference.load(
      AppLocalizations.supportedLocales,
    );
    final location = await DocumentLocationPreference.load();
    await location.set(
      const DocumentLocation(handle: '/tmp/sync', label: '/tmp/sync'),
    );

    await tester.pumpWidget(
      CirrhyApp(
        localePreference: locale,
        locationPreference: location,
        directory: FakeDocumentDirectory(),
      ),
    );
    await tester.pumpAndSettle();

    for (final (text, style) in painted(tester)) {
      expect(style.color, isNotNull, reason: '"$text" has no colour');
    }
  });

  test('the theme gives every text role a colour', () {
    // The roles nothing maps still have to come out of the merge with one,
    // because the next screen will reach for one of them.
    for (final (name, theme) in [
      ('light', cirrhyLightTheme()),
      ('dark', cirrhyDarkTheme()),
    ]) {
      final text = theme.textTheme;
      final roles = <String, TextStyle?>{
        'displayLarge': text.displayLarge,
        'displayMedium': text.displayMedium,
        'displaySmall': text.displaySmall,
        'headlineLarge': text.headlineLarge,
        'headlineMedium': text.headlineMedium,
        'headlineSmall': text.headlineSmall,
        'titleLarge': text.titleLarge,
        'titleMedium': text.titleMedium,
        'titleSmall': text.titleSmall,
        'bodyLarge': text.bodyLarge,
        'bodyMedium': text.bodyMedium,
        'bodySmall': text.bodySmall,
        'labelLarge': text.labelLarge,
        'labelMedium': text.labelMedium,
        'labelSmall': text.labelSmall,
      };
      roles.forEach((role, style) {
        expect(style?.color, isNotNull, reason: '$name $role has no colour');
      });
    }
  });
}
