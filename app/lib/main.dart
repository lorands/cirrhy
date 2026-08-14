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

import 'dart:async';

import 'package:flutter/material.dart';

import 'data/document_session.dart';
import 'l10n/generated/app_localizations.dart';
import 'settings/document_location_preference.dart';
import 'settings/locale_preference.dart';
import 'settings/settings_screen.dart';
import 'settings/theme_preference.dart';
import 'shell/app_shell.dart';
import 'storage/document_backups.dart';
import 'storage/document_directory.dart';
import 'theme/theme.dart';

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
  final theme = await ThemePreference.load();
  runApp(
    CirrhyApp(
      localePreference: locale,
      locationPreference: location,
      directory: DocumentDirectory.forPlatform(),
      themePreference: theme,
    ),
  );
}

class CirrhyApp extends StatelessWidget {
  const CirrhyApp({
    super.key,
    this.localePreference,
    this.locationPreference,
    this.directory,
    this.themePreference,
  });

  /// Null in tests and until the stored choice has been read; the app then
  /// simply follows the system, which is the default anyway.
  final LocalePreference? localePreference;

  /// Null in tests that do not exercise storage. When it is present and holds
  /// no folder, the app opens on the first-run screen (§4.6).
  final DocumentLocationPreference? locationPreference;

  final DocumentDirectory? directory;

  /// Null in tests that do not exercise theming; the app then simply follows
  /// the system, which is the default anyway — the same shape as
  /// [localePreference].
  final ThemePreference? themePreference;

  @override
  Widget build(BuildContext context) {
    final locale = localePreference;
    final theme = themePreference;
    if (locale == null && theme == null) return _app(null, null);

    // Rebuilds MaterialApp when the user switches either preference, so the
    // change is immediate rather than waiting for a restart. Listenable.merge
    // tolerates the null entry when only one of the two is wired up.
    return ListenableBuilder(
      listenable: Listenable.merge([locale, theme]),
      builder: (context, _) => _app(locale, theme),
    );
  }

  Widget _app(LocalePreference? locale, ThemePreference? theme) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: cirrhyLightTheme(),
      darkTheme: cirrhyDarkTheme(),
      // Follows the OS by default; both schemes are fully specified, so
      // there is no "unfinished" side to hide behind a forced default. A
      // stored override, once loaded, takes over from here.
      themeMode: theme?.mode ?? ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Null means "follow the OS", which is the default state. When set,
      // Flutter passes it to localeListResolutionCallback as the sole
      // preference, so resolveLocale still guards the fallback.
      locale: locale?.locale,
      localeListResolutionCallback: resolveLocale,
      home: _Home(
        localePreference: locale,
        locationPreference: locationPreference,
        directory: directory,
        themePreference: theme,
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
  const _Home({
    this.localePreference,
    this.locationPreference,
    this.directory,
    this.themePreference,
  });

  final LocalePreference? localePreference;
  final DocumentLocationPreference? locationPreference;
  final DocumentDirectory? directory;
  final ThemePreference? themePreference;

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

  /// The open document, once the async pieces (device id, backups) resolve.
  ///
  /// Created even during first run: the session listens to the location
  /// preference, so the moment the first-run screen's picker lands on a
  /// folder, the session opens it — no second wiring path for `onContinue`.
  DocumentSession? _session;

  @override
  void initState() {
    super.initState();
    final location = widget.locationPreference;
    final directory = widget.directory;
    if (location != null && directory != null) {
      unawaited(_startSession(directory, location));
    }
  }

  Future<void> _startSession(
    DocumentDirectory directory,
    DocumentLocationPreference location,
  ) async {
    DocumentBackups? backup;
    try {
      backup = await DocumentBackups.openAppPrivate();
    } on Object {
      // No app-private storage means no backups, not no app. The repository
      // already treats a failed snapshot as survivable (§4.3); failing to
      // even create the folder is the same trade one step earlier.
    }
    final session = await DocumentSession.start(
      directory: directory,
      locationPreference: location,
      backup: backup,
    );
    if (!mounted) {
      session.dispose();
      return;
    }
    setState(() => _session = session);
    // A no-op until a folder is chosen; on first run the session's location
    // listener takes over from here.
    await session.open();
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

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
          themePreference: widget.themePreference,
          firstRun: true,
          onContinue: () => setState(() => _firstRun = false),
        ),
      );
    }

    return AppShell(
      localePreference: locale,
      locationPreference: location,
      directory: directory,
      themePreference: widget.themePreference,
      session: _session,
    );
  }
}
