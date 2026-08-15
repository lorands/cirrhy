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

import 'package:cirrhy/theme/tokens.dart';
import 'package:cirrhy/widgets/entry_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// F2 — the merge surfaced: the snackbar after a refresh that brought in
/// records, and the tinted "new from another device" rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a refresh that merged changes announces the count, singular '
      'and plural', (tester) async {
    var now = DateTime.utc(2026, 8, 13, 9);
    final harness = await SyncHarness.open(clock: () => now);
    addTearDown(harness.session.dispose);
    await pumpSyncShell(tester, harness);

    await harness.writeAsOtherDevice((doc) => doc.put(entryAt('e1', now)));
    await harness.session.refresh();
    await tester.pump();

    expect(find.text('Synced — merged 1 change'), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
    // Fully retire this snackbar, so the next one is shown rather than
    // queued behind it.
    await drainSnackBars(tester);

    now = now.add(const Duration(hours: 1));
    await harness.writeAsOtherDevice(
      (doc) => doc.put(entryAt('e2', now)).put(entryAt('e3', now)),
    );
    await harness.session.refresh();
    await tester.pump();

    expect(find.text('Synced — merged 2 changes'), findsOneWidget);
    await drainSnackBars(tester);

    // A refresh that found nothing announces nothing.
    await harness.session.refresh();
    await tester.pump();
    expect(find.textContaining('Synced — merged'), findsNothing);
  });

  testWidgets('the announcement is translated — Hungarian plural', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 8, 13, 9);
    final harness = await SyncHarness.open(clock: () => now);
    addTearDown(harness.session.dispose);
    await pumpSyncShell(tester, harness, locale: const Locale('hu'));

    await harness.writeAsOtherDevice(
      (doc) => doc.put(entryAt('e1', now)).put(entryAt('e2', now)),
    );
    await harness.session.refresh();
    await tester.pump();

    expect(
      find.text('Szinkronizálva — 2 változás összefésülve'),
      findsOneWidget,
    );
    await drainSnackBars(tester);
  });

  testWidgets('merged-in rows are tinted and captioned until a later merge '
      'brings different ones', (tester) async {
    var now = DateTime.utc(2026, 8, 13, 9);
    final harness = await SyncHarness.open(clock: () => now);
    addTearDown(harness.session.dispose);
    await pumpSyncShell(tester, harness);

    await harness.session.put(entryAt('mine', now, description: 'My own row'));
    await tester.pump();

    now = now.add(const Duration(hours: 1));
    await harness.writeAsOtherDevice(
      (doc) => doc.put(entryAt('theirs', now, description: 'From the laptop')),
    );
    await harness.session.refresh();
    await tester.pump();

    expect(find.text('new from another device'), findsOneWidget);
    // The caption sits inside the merged row, and only that row is tinted.
    final rows = tester.widgetList<EntryRow>(find.byType(EntryRow)).toList();
    expect(rows, hasLength(2));
    final tinted = find.descendant(
      of: find.byType(EntryRow),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.color == CirrhyColors.light.brandSubtle,
      ),
    );
    expect(tinted, findsOneWidget);
    await drainSnackBars(tester);

    // An empty-handed refresh leaves the mark standing — with reads a couple
    // of seconds apart after a resume, clearing on those would take it away
    // before anyone read it.
    await harness.session.refresh();
    await tester.pump();
    expect(find.text('new from another device'), findsOneWidget);
    expect(tinted, findsOneWidget);

    // A merge that brings something replaces the set: the mark moves rather
    // than accumulating.
    now = now.add(const Duration(hours: 1));
    await harness.writeAsOtherDevice(
      (doc) =>
          doc.put(entryAt('theirs-2', now, description: 'Also the laptop')),
    );
    await harness.session.refresh();
    await tester.pump();

    expect(find.text('new from another device'), findsOneWidget);
    expect(tinted, findsOneWidget);
    final marked = tester.widget<EntryRow>(
      find.ancestor(
        of: find.text('new from another device'),
        matching: find.byType(EntryRow),
      ),
    );
    expect(marked.entry.id, 'theirs-2');
  });
}
