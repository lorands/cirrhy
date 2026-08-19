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

import 'dart:convert';
import 'dart:io';

import 'package:cirrhy/l10n/generated/app_localizations.dart';
import 'package:cirrhy/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The languages the product promises. Adding one here without shipping its
/// ARB file fails the suite, which is the point — this list is the contract.
const shipped = {'hu', 'en', 'es', 'it', 'de'};

void main() {
  test('every promised language is shipped, and nothing extra sneaks in', () {
    final actual = AppLocalizations.supportedLocales
        .map((l) => l.languageCode)
        .toSet();
    expect(actual, shipped);
  });

  test('the App Store advertises exactly the shipped languages', () {
    // gen-l10n creates no .lproj folders, so the store page's language list is
    // read from CFBundleLocalizations and nowhere else. That plist is the only
    // place outside this file a new language has to be added to, which is
    // exactly why it is asserted rather than trusted — see
    // docs/release/app-store.md.
    final plist = File('ios/Runner/Info.plist');
    expect(plist.existsSync(), isTrue, reason: 'missing ${plist.path}');

    final array = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist.readAsStringSync());
    expect(
      array,
      isNotNull,
      reason: 'Info.plist declares no CFBundleLocalizations',
    );

    final declared = RegExp(
      r'<string>(\w+)</string>',
    ).allMatches(array!.group(1)!).map((m) => m.group(1)!).toSet();
    expect(declared, shipped);
  });

  test('no language is missing a key the template defines', () {
    // gen-l10n is happy to emit a locale that silently inherits English for
    // anything it forgot. Comparing the ARB files directly is the only way to
    // see that, since the generated class papers over it.
    Set<String> keysOf(String code) {
      final file = File('lib/l10n/app_$code.arb');
      expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      // @@locale is metadata; @key entries are translator notes on the real key.
      return json.keys.where((k) => !k.startsWith('@')).toSet();
    }

    final template = keysOf('en');
    expect(template, isNotEmpty);
    for (final code in shipped) {
      expect(
        keysOf(code),
        template,
        reason: '$code disagrees with the template',
      );
    }
  });

  test('an unsupported locale falls back to English, not the alphabet', () {
    // gen-l10n sorts supportedLocales, so `de` sits first and Flutter's stock
    // fallback would hand German to every unmatched device.
    expect(AppLocalizations.supportedLocales.first, const Locale('de'));

    final resolved = resolveLocale([
      const Locale('ja'),
      const Locale('fr'),
    ], AppLocalizations.supportedLocales);
    expect(resolved, const Locale('en'));
  });

  test('a region variant resolves to its language', () {
    final resolved = resolveLocale([
      const Locale('es', 'MX'),
    ], AppLocalizations.supportedLocales);
    expect(resolved, const Locale('es'));
  });

  test('the device preference order is honoured', () {
    final resolved = resolveLocale([
      const Locale('ja'),
      const Locale('hu'),
      const Locale('de'),
    ], AppLocalizations.supportedLocales);
    expect(resolved, const Locale('hu'));
  });

  test('the picker label is not a copy of one of its values', () async {
    // These read identically if languageSystem is reused as the field label,
    // which is what the first build actually did.
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(
        l10n.languageLabel,
        isNot(l10n.languageSystem),
        reason: '${locale.languageCode} labels the field with a value',
      );
    }
  });

  test('no locale is given an empty or untranslated body', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(l10n.timerIdleHint, isNotEmpty);
      expect(l10n.languageName, isNotEmpty);
      expect(
        l10n.appTitle,
        'Cirrhy',
        reason: 'the brand name is not translated',
      );
    }
  });

  testWidgets('the UI renders in each language', (tester) async {
    // hu and de are the useful pair to assert on: distinct strings, and hu is
    // the one language whose absence would be least noticed by an English
    // reader reviewing a diff.
    for (final (code, expected) in [
      ('hu', 'Magyar'),
      ('de', 'Deutsch'),
      ('es', 'Español'),
      ('it', 'Italiano'),
      ('en', 'English'),
    ]) {
      final l10n = await AppLocalizations.delegate.load(Locale(code));
      expect(l10n.languageName, expected);
    }

    await tester.pumpWidget(const CirrhyApp());
    await tester.pumpAndSettle();
    expect(find.text('Cirrhy'), findsOneWidget);
  });

  testWidgets('the real app picks up the device locale', (tester) async {
    // The end-to-end check: delegates, resolution and rendering together.
    // Loading an ARB directly would pass even with MaterialApp unwired. The
    // idle timer card's hint text is the proof: it renders unconditionally,
    // with no session and no folder chosen, which is exactly the state
    // `const CirrhyApp()` boots into here.
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

    for (final (locale, expected) in [
      (const Locale('hu'), 'Min dolgozol?'),
      (const Locale('de'), 'Woran arbeitest du?'),
      // Unsupported: must land on English rather than alphabetically-first German.
      (const Locale('ja'), 'What are you working on?'),
    ]) {
      tester.binding.platformDispatcher.localesTestValue = [locale];
      await tester.pumpWidget(const CirrhyApp());
      await tester.pumpAndSettle();
      expect(
        find.text(expected),
        findsOneWidget,
        reason: 'locale ${locale.languageCode} did not render its own copy',
      );
    }
  });
}
