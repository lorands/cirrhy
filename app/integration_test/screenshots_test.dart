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

// App Store screenshots, captured from the real app on a real simulator.
//
// Not a test — nothing is asserted. It exists because store screenshots have
// to be exact device resolutions of a populated app, and the two honest ways
// to get that are a person tapping through a simulator or this. Run it with
// tool/gen_screenshots.sh, which supplies the seed document and the device.
//
// The app is built through `CirrhyApp` with the same wiring `main()` uses, so
// what is captured is the shipping UI and not a lookalike. Only two things are
// substituted: the document is a seeded copy of the example file, and the
// directory is the plain-path implementation, because a simulator has no
// security-scoped bookmark to resolve.

import 'dart:io';

import 'package:cirrhy/l10n/generated/app_localizations.dart';
import 'package:cirrhy/main.dart';
import 'package:cirrhy/settings/document_location_preference.dart';
import 'package:cirrhy/settings/locale_preference.dart';
import 'package:cirrhy/settings/theme_preference.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/storage/path_document_directory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Absolute host path to the document to display. The simulator shares the
/// Mac's filesystem, so it can read it directly. An Android emulator cannot
/// see the host at all, so there [seedOnDevice] is what exists instead.
const seedPath = String.fromEnvironment('CIRRHY_SEED');

/// Where tool/gen_screenshots.sh adb-pushes the seed on Android. The app's own
/// external files directory is the one place adb can write and the app can
/// read back without asking for a runtime permission.
const seedOnDevice = 'cirrhy-seed.json';

/// The seed, wherever this platform keeps it.
Future<File> resolveSeed() async {
  if (seedPath.isNotEmpty) {
    final host = File(seedPath);
    if (host.existsSync()) return host;
  }
  if (Platform.isAndroid) {
    final external = await getExternalStorageDirectory();
    if (external != null) {
      final pushed = File('${external.path}/$seedOnDevice');
      if (pushed.existsSync()) return pushed;
    }
  }
  fail(
    'no seed document — the simulator reads --dart-define=CIRRHY_SEED, and '
    'Android reads what tool/gen_screenshots.sh pushed to $seedOnDevice. '
    'Run the script rather than flutter drive directly.',
  );
}

/// Which language to render the UI in — the store listing can carry a
/// screenshot set per locale.
const seedLocale = String.fromEnvironment('CIRRHY_LOCALE', defaultValue: 'en');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture the store screenshots', (tester) async {
    final seed = await resolveSeed();

    // A real directory inside the app's own container, holding a copy of the
    // seed. The app then opens it exactly as it would a user's folder.
    final support = await getApplicationSupportDirectory();
    final folder = Directory('${support.path}/screenshot-document');
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    await folder.create(recursive: true);
    await seed.copy('${folder.path}/cirrhy.json');

    SharedPreferences.setMockInitialValues({
      'settings.documentLocation': DocumentLocation(
        handle: folder.path,
        label: 'Dropbox / Cirrhy',
      ).encode(),
      'settings.locale': seedLocale,
      // Pinned rather than left to the simulator, so a rerun cannot silently
      // produce a light set one day and a dark set the next.
      'settings.themeMode': 'light',
      'device.id': '4f1c2a90-7b3e-4d55-9c81-0a6e2f3b8d41',
    });

    await tester.pumpWidget(
      CirrhyApp(
        localePreference: await LocalePreference.load(
          AppLocalizations.supportedLocales,
        ),
        locationPreference: await DocumentLocationPreference.load(),
        directory: const PathDocumentDirectory(),
        themePreference: await ThemePreference.load(),
      ),
    );

    // Opening the document is several async hops — app-private backups, the
    // device id, then the first read-and-merge of 1,400 entries. Waiting a
    // fixed number of frames races that, and losing the race is silent: the
    // capture succeeds and writes a blank surface at the right dimensions,
    // which is indistinguishable from success until someone opens the file.
    // So every capture waits for something only a populated screen renders.
    Future<void> waitFor(Finder finder, String what) async {
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) return;
      }
      fail('$what never rendered — the capture would have been blank');
    }

    // Android needs the surface converted before it can be read back; iOS
    // captures directly and throws if asked.
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();

    Future<void> shot(String name, Finder proof, String what) async {
      await waitFor(proof, what);
      // One more settled frame, so the capture is of a composited tree rather
      // than the frame that merely built it.
      await tester.pump(const Duration(milliseconds: 400));
      await binding.takeScreenshot(name);
    }

    // The running timer's description comes from the document, so finding it
    // proves the file was read, not merely that the app booted.
    await shot(
      '01-timer',
      find.textContaining('Cursor pagination'),
      'the timer screen',
    );

    for (final (icon, name, proof, what) in [
      (Icons.bar_chart, '02-reports', 'Telemetry Platform', 'the reports'),
      (Icons.folder_outlined, '03-projects', 'Meridian Labs', 'the projects'),
    ]) {
      await tester.tap(find.byIcon(icon).first);
      await tester.pump(const Duration(milliseconds: 200));
      await shot(name, find.textContaining(proof).first, what);
    }
  });
}
