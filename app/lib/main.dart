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

import 'l10n/generated/app_localizations.dart';
import 'settings/locale_preference.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read before the first frame so the app never flashes the system language
  // and then swaps to the chosen one.
  final locale = await LocalePreference.load(AppLocalizations.supportedLocales);
  runApp(CirrhyApp(localePreference: locale));
}

class CirrhyApp extends StatelessWidget {
  const CirrhyApp({super.key, this.localePreference});

  /// Null in tests and until the stored choice has been read; the app then
  /// simply follows the system, which is the default anyway.
  final LocalePreference? localePreference;

  @override
  Widget build(BuildContext context) {
    final preference = localePreference;
    if (preference == null) return _app(null);

    // Rebuilds MaterialApp when the user switches, so the change is immediate
    // rather than waiting for a restart.
    return ListenableBuilder(
      listenable: preference,
      builder: (context, _) => _app(preference),
    );
  }

  Widget _app(LocalePreference? preference) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: cirrhyLightTheme(),
      darkTheme: cirrhyDarkTheme(),
      // Follows the OS. Both schemes are fully specified, so there is no
      // "unfinished" side to hide behind a forced default.
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Null means "follow the OS", which is the default state. When set,
      // Flutter passes it to localeListResolutionCallback as the sole
      // preference, so resolveLocale still guards the fallback.
      locale: preference?.locale,
      localeListResolutionCallback: resolveLocale,
      home: _Placeholder(localePreference: preference),
    );
  }
}

/// Picks the best supported locale for the device's preference list.
///
/// This exists for the last line only. Flutter's built-in resolution is fine
/// at matching, but when nothing matches it falls back to
/// `supportedLocales.first` — and gen-l10n emits that list sorted by locale
/// code, so `de` is first. A Japanese or French device would get German. The
/// fallback has to be English, and it has to be stated rather than left to the
/// alphabet: adding a language must never silently change it.
///
/// Matching on `languageCode` alone is deliberate. `es-MX` should get Spanish
/// rather than English, and none of the five ship region variants yet.
@visibleForTesting
Locale resolveLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  for (final locale in preferred ?? const <Locale>[]) {
    for (final candidate in supported) {
      if (candidate.languageCode == locale.languageCode) return candidate;
    }
  }
  return const Locale('en');
}

/// Deliberately empty.
///
/// DESIGN.md §9: the storage engine is built first, standalone and headless,
/// because it is the part that can lose user data. Screens come after it, on
/// top of the design system in the Penpot file.
class _Placeholder extends StatelessWidget {
  const _Placeholder({this.localePreference});

  final LocalePreference? localePreference;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.x8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.appTitle, style: text.headlineLarge),
              const SizedBox(height: Space.x2),
              Text(
                l10n.placeholderBody,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: Space.x6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.x3,
                  vertical: Space.x2,
                ),
                decoration: BoxDecoration(
                  color: colors.brandSubtle,
                  borderRadius: BorderRadius.circular(Radii.full),
                ),
                child: Text(
                  'package:cirrhy_merge',
                  style: text.labelSmall?.copyWith(color: colors.brand),
                ),
              ),
              if (localePreference != null) ...[
                const SizedBox(height: Space.x8),
                LanguagePicker(preference: localePreference!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Scaffolding, not the finished settings UI.
///
/// The language override needs somewhere to be exercised before a settings
/// screen exists, and having it on screen is how the choice gets checked on a
/// real phone and a real desktop. It moves into settings when that screen is
/// designed; the [LocalePreference] behind it does not change.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, required this.preference});

  final LocalePreference preference;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);

    return DropdownMenu<Locale?>(
      initialSelection: preference.locale,
      // Not languageSystem: that is one of the values, and a label repeating
      // the selected value tells the reader nothing.
      label: Text(l10n.languageLabel),
      onSelected: preference.set,
      textStyle: Theme.of(context).textTheme.bodyMedium,
      dropdownMenuEntries: [
        DropdownMenuEntry(value: null, label: l10n.languageSystem),
        // Each language is listed in itself — a picker that says "Hungarian"
        // is no use to someone who cannot read the current language. That is
        // what the languageName key exists for.
        for (final locale in AppLocalizations.supportedLocales)
          DropdownMenuEntry(
            value: locale,
            label: lookupAppLocalizations(locale).languageName,
            leadingIcon: preference.locale?.languageCode == locale.languageCode
                ? Icon(Icons.check, size: 18, color: colors.brand)
                : const SizedBox(width: 18),
          ),
      ],
    );
  }
}
