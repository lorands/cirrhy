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
import 'settings/document_location_preference.dart';
import 'settings/locale_preference.dart';
import 'settings/settings_screen.dart';
import 'storage/document_directory.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read before the first frame so the app never flashes the system language
  // and then swaps to the chosen one.
  final locale = await LocalePreference.load(AppLocalizations.supportedLocales);
  // Read, but deliberately not verified here. Checking that the handle still
  // resolves means a platform round trip — on iOS, resolving a bookmark and
  // starting a security-scoped access — and that does not belong in front of
  // the first frame. The preferences screen checks when it opens (§4.4).
  final location = await DocumentLocationPreference.load();
  runApp(
    CirrhyApp(
      localePreference: locale,
      locationPreference: location,
      directory: DocumentDirectory.forPlatform(),
    ),
  );
}

class CirrhyApp extends StatelessWidget {
  const CirrhyApp({
    super.key,
    this.localePreference,
    this.locationPreference,
    this.directory,
  });

  /// Null in tests and until the stored choice has been read; the app then
  /// simply follows the system, which is the default anyway.
  final LocalePreference? localePreference;

  /// Null in tests that do not exercise storage. When it is present and holds
  /// no folder, the app opens on the first-run screen (§4.6).
  final DocumentLocationPreference? locationPreference;

  final DocumentDirectory? directory;

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
      home: _Home(
        localePreference: preference,
        locationPreference: locationPreference,
        directory: directory,
      ),
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

/// First run, or the app proper.
class _Home extends StatefulWidget {
  const _Home({this.localePreference, this.locationPreference, this.directory});

  final LocalePreference? localePreference;
  final DocumentLocationPreference? locationPreference;
  final DocumentDirectory? directory;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  /// Decided once, at startup, and not re-derived from the preference.
  ///
  /// If this tracked `isChosen` the screen would swap itself out the instant
  /// the folder was picked, taking the "will be created" / "will be merged"
  /// confirmation with it before anyone read it.
  late bool _firstRun = widget.locationPreference?.isChosen == false;

  @override
  Widget build(BuildContext context) {
    final locale = widget.localePreference;
    final location = widget.locationPreference;
    final directory = widget.directory;

    if (_firstRun && locale != null && location != null && directory != null) {
      return ListenableBuilder(
        listenable: location,
        builder: (context, _) => SettingsScreen(
          localePreference: locale,
          locationPreference: location,
          directory: directory,
          firstRun: true,
          onContinue: () => setState(() => _firstRun = false),
        ),
      );
    }

    return _Placeholder(
      localePreference: locale,
      locationPreference: location,
      directory: directory,
    );
  }
}

/// Deliberately empty.
///
/// DESIGN.md §9: the storage engine is built first, standalone and headless,
/// because it is the part that can lose user data. Screens come after it, on
/// top of the design system in the Penpot file. What is here now is the way in
/// to preferences and nothing else.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    this.localePreference,
    this.locationPreference,
    this.directory,
  });

  final LocalePreference? localePreference;
  final DocumentLocationPreference? locationPreference;
  final DocumentDirectory? directory;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final locale = localePreference;
    final location = locationPreference;
    final directory = this.directory;
    final canOpenSettings =
        locale != null && location != null && directory != null;

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (canOpenSettings)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: l10n.settingsTitle,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(
                    localePreference: locale,
                    locationPreference: location,
                    directory: directory,
                  ),
                ),
              ),
            ),
        ],
      ),
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
              if (location != null) ...[
                const SizedBox(height: Space.x6),
                ListenableBuilder(
                  listenable: location,
                  builder: (context, _) => Text(
                    location.location?.label ?? l10n.storageNotChosen,
                    style: text.labelSmall?.copyWith(color: colors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
