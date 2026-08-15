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
import 'package:cirrhy/shell/app_shell.dart';
import 'package:cirrhy/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// G1 — the sync-status line, in the rail and in the narrow layout's strip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const footer = Key('railSyncFooter');
  const strip = Key('barSyncStatus');

  void goWide(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
  }

  /// The narrowest screen the app ships against (Mate 10 Pro width), so the
  /// strip's own layout is under test and not just its presence — an overflow
  /// here would throw.
  void goNarrow(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
  }

  testWidgets('nothing before the first refresh, the synced time after it, '
      'and the warning while unreachable', (tester) async {
    goWide(tester);
    var now = DateTime.utc(2026, 8, 13, 9);
    final harness = await SyncHarness.open(clock: () => now);
    addTearDown(harness.session.dispose);
    // No recovery pieces, so the A3 dialog stays out of the footer's way.
    await pumpSyncShell(tester, harness, withRecovery: false);

    // Ready but never refreshed: the session opening is not a sync, so the
    // footer claims nothing.
    expect(find.byKey(footer), findsNothing);

    now = now.add(const Duration(minutes: 3));
    await harness.session.refresh();
    await tester.pump();

    final hm = DateFormat.Hm('en').format(now.toLocal());
    expect(find.byKey(footer), findsOneWidget);
    expect(find.text('Synced · $hm'), findsOneWidget);

    harness.store.unavailable = true;
    await harness.session.refresh();
    await tester.pump();

    expect(find.text('Folder unreachable'), findsOneWidget);
    expect(find.textContaining('Synced ·'), findsNothing);
  });

  testWidgets('a shell without a session shows no footer at all', (
    tester,
  ) async {
    goWide(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: cirrhyLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const AppShell(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(footer), findsNothing);
  });

  testWidgets('the narrow layout has no rail, and says the same thing above '
      'the tab bar instead', (tester) async {
    goNarrow(tester);
    var now = DateTime.utc(2026, 8, 13, 9);
    final harness = await SyncHarness.open(clock: () => now);
    addTearDown(harness.session.dispose);
    await pumpSyncShell(tester, harness, withRecovery: false);

    // Same rule as the rail: nothing to claim before the first refresh.
    expect(find.byKey(strip), findsNothing);

    now = now.add(const Duration(minutes: 3));
    await harness.session.refresh();
    await tester.pump();

    expect(find.byKey(footer), findsNothing);
    expect(find.byKey(strip), findsOneWidget);
    expect(
      find.text('Synced · ${DateFormat.Hm('en').format(now.toLocal())}'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the line re-reads the file', (tester) async {
    goNarrow(tester);
    var now = DateTime.utc(2026, 8, 13, 9);
    final harness = await SyncHarness.open(clock: () => now);
    addTearDown(harness.session.dispose);
    await pumpSyncShell(tester, harness, withRecovery: false);

    // The line only exists once there is a refresh to report, so give it one.
    await harness.session.refresh();
    await tester.pump();

    await harness.writeAsOtherDevice(
      (doc) => doc.put(entryAt('elsewhere', now)),
    );
    expect(harness.session.document.entries, isEmpty);

    // Deliberately no pumpAndSettle anywhere in here: it walks the fake clock
    // forward in 100ms steps, and the point of this test is that the merge
    // came from the tap rather than from the schedule's next read.
    final reads = harness.store.reads;
    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.byKey(strip));
    await harness.session.idle;
    await tester.pump();

    expect(harness.store.reads, greaterThan(reads));
    expect(harness.session.document.entries.keys, ['elsewhere']);
  });
}
