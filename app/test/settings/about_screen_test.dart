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

import 'package:cirrhy/about/version.dart';
import 'package:cirrhy/l10n/generated/app_localizations.dart';
import 'package:cirrhy/settings/about_screen.dart';
import 'package:cirrhy/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpAbout(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: cirrhyLightTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: const AboutScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the wordmark, the version line and the tagline', (
    tester,
  ) async {
    await pumpAbout(tester);

    expect(find.text('Cirrhy'), findsWidgets); // app bar title + wordmark
    expect(find.text('Version $appVersion · Apache 2.0'), findsOneWidget);
    expect(
      find.text(
        'A personal time tracker built around one promise: all your data '
        'in a single file you own.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Circadian rhythm — the clock you already run on.'),
      findsOneWidget,
    );
  });

  testWidgets('the Licence row opens the licence page', (tester) async {
    await pumpAbout(tester);

    await tester.tap(find.text('Licence'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('the Third-party notices row opens the same licence page', (
    tester,
  ) async {
    await pumpAbout(tester);

    await tester.tap(find.text('Third-party notices'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('renders in Hungarian', (tester) async {
    await pumpAbout(tester, locale: const Locale('hu'));

    expect(find.text('A Cirrhy névjegye'), findsWidgets);
    expect(find.text('$appVersion. verzió · Apache 2.0'), findsOneWidget);
  });
}
