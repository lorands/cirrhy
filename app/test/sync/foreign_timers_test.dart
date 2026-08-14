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
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// F1 — the two-timers reconciliation banner on the timer screen (§3.6).
///
/// Pumps with explicit durations throughout: the banner and the running card
/// tick every second, so pumpAndSettle would never settle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const banner = Key('foreignTimersBanner');

  testWidgets('a merged foreign timer raises the banner; Keep both hides it '
      'for that set and re-arms for a different one', (tester) async {
    var now = DateTime.utc(2026, 8, 13, 14);
    final harness = await SyncHarness.open(clock: () => now);
    addTearDown(harness.session.dispose);
    await pumpSyncShell(tester, harness);

    expect(find.byKey(banner), findsNothing);

    // This device tracks too, so both cards have something to show.
    await harness.session.startTimer(description: 'Landing page');
    await tester.pump();

    final startedAt = now.subtract(const Duration(minutes: 47));
    await harness.writeAsOtherDevice(
      (doc) =>
          doc.put(foreignTimerAt('phone', startedAt, description: 'On call')),
    );
    await harness.session.refresh();
    await tester.pump();

    expect(find.byKey(banner), findsOneWidget);
    expect(find.text('Two timers were running'), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('Another device'), findsOneWidget);
    expect(find.text('On call'), findsOneWidget);
    expect(find.text('Keep both running'), findsOneWidget);
    expect(find.text('Stop it now'), findsOneWidget);
    final hm = DateFormat.Hm('en').format(startedAt.toLocal());
    expect(find.text('started $hm'), findsOneWidget);

    // Let the merge snackbar expire and animate out, so it cannot sit over
    // the button the test is about to press.
    await drainSnackBars(tester);

    // The actions sit at the bottom of a tall section on a short surface.
    await tester.ensureVisible(find.byKey(const Key('keepBothButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('keepBothButton')));
    await tester.pump();
    expect(find.byKey(banner), findsNothing);

    // The same set arriving again stays acknowledged.
    await harness.session.refresh();
    await tester.pump();
    expect(find.byKey(banner), findsNothing);

    // A different foreign timer is a new question.
    await harness.writeAsOtherDevice(
      (doc) => doc.put(foreignTimerAt('tablet', now)),
    );
    await harness.session.refresh();
    await tester.pump();
    expect(find.byKey(banner), findsOneWidget);

    // Drain the queued snackbar before teardown.
    await drainSnackBars(tester);
  });

  testWidgets('Stop it now files the foreign interval as a listed entry and '
      'clears the prompt', (tester) async {
    var now = DateTime.utc(2026, 8, 13, 14);
    final harness = await SyncHarness.open(clock: () => now);
    addTearDown(harness.session.dispose);
    await pumpSyncShell(tester, harness);

    final startedAt = now.subtract(const Duration(minutes: 47));
    await harness.writeAsOtherDevice(
      (doc) =>
          doc.put(foreignTimerAt('phone', startedAt, description: 'On call')),
    );
    await harness.session.refresh();
    await tester.pump();
    expect(find.byKey(banner), findsOneWidget);

    // Expire the merge snackbar and scroll the stop button into reach.
    await drainSnackBars(tester);
    await tester.ensureVisible(
      find.byKey(const Key('stopForeignButton-phone')),
    );
    await tester.pump();

    now = now.add(const Duration(minutes: 2));
    await tester.tap(find.byKey(const Key('stopForeignButton-phone')));
    await harness.session.idle;
    await tester.pump();

    // The prompt is gone because the timer is gone — it became an entry.
    expect(find.byKey(banner), findsNothing);
    final logged = harness.session.document.entries.values.single;
    expect(logged.start, startedAt);
    expect(logged.stop, now);
    expect(logged.description, 'On call');
    // And the row simply appears in the day list.
    expect(find.text('On call'), findsOneWidget);

    // Drain any remaining snackbar before teardown.
    await drainSnackBars(tester);
  });
}
