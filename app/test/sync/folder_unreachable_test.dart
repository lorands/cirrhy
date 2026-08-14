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

import 'package:cirrhy/data/document_session.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// A3 — the folder-unreachable dialog: shown on the transition into
/// unavailable, dismissed once, re-armed only by a fresh transition (§4.4).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final title = find.text("Can't reach your folder");

  testWidgets('appears once per transition, Not now dismisses for the whole '
      'outage, and a second outage re-arms it', (tester) async {
    final harness = await SyncHarness.open();
    addTearDown(harness.session.dispose);
    await pumpSyncShell(tester, harness);
    expect(title, findsNothing);

    harness.store.unavailable = true;
    await harness.session.refresh();
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);

    // Further notifies while already unavailable must not stack dialogs.
    await harness.session.refresh();
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);

    await tester.tap(find.byKey(const Key('notNowButton')));
    await tester.pumpAndSettle();
    expect(title, findsNothing);

    // Still unavailable, still dismissed.
    await harness.session.refresh();
    await tester.pumpAndSettle();
    expect(title, findsNothing);

    // The folder comes back, then goes away again — a fresh transition.
    harness.store.unavailable = false;
    await harness.session.refresh();
    await tester.pumpAndSettle();
    expect(harness.session.status, SessionStatus.ready);

    harness.store.unavailable = true;
    await harness.session.refresh();
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);
  });

  testWidgets('re-selecting a reachable folder relocates the document and '
      'closes the dialog', (tester) async {
    final harness = await SyncHarness.open();
    addTearDown(harness.session.dispose);
    await pumpSyncShell(tester, harness);

    harness.store.unavailable = true;
    await harness.session.refresh();
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);

    const newLocation = DocumentLocation(handle: 'memory:b', label: 'B');
    harness.directory.picked = newLocation;

    await tester.tap(find.byKey(const Key('reselectFolderButton')));
    await tester.pump();
    await harness.session.idle;
    await tester.pumpAndSettle();

    expect(title, findsNothing);
    expect(harness.session.status, SessionStatus.ready);
    // Relocation is a save (§4.6): the new folder now holds the document.
    expect(harness.directory.storeAt(newLocation).bytes, isNotNull);
  });

  testWidgets('a failed pick keeps the dialog up and says what happened', (
    tester,
  ) async {
    final harness = await SyncHarness.open();
    addTearDown(harness.session.dispose);
    await pumpSyncShell(tester, harness);

    harness.store.unavailable = true;
    await harness.session.refresh();
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);

    harness.directory.failsToPick = true;
    await tester.tap(find.byKey(const Key('reselectFolderButton')));
    await tester.pumpAndSettle();

    expect(title, findsOneWidget);
    expect(find.text('That folder could not be opened.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('notNowButton')));
    await tester.pumpAndSettle();
  });

  testWidgets('a shell without the recovery pieces shows no dead-end '
      'dialog', (tester) async {
    final harness = await SyncHarness.open();
    addTearDown(harness.session.dispose);
    await pumpSyncShell(tester, harness, withRecovery: false);

    harness.store.unavailable = true;
    await harness.session.refresh();
    await tester.pumpAndSettle();

    expect(harness.session.status, SessionStatus.unavailable);
    expect(title, findsNothing);
  });
}
