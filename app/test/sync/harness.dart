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
import 'package:cirrhy/l10n/generated/app_localizations.dart';
import 'package:cirrhy/settings/document_location_preference.dart';
import 'package:cirrhy/shell/app_shell.dart';
import 'package:cirrhy/storage/document_location.dart';
import 'package:cirrhy/theme/theme.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_directory.dart';

/// The one location every sync test shares — an in-memory store, because real
/// file IO cannot settle inside testWidgets' fake-async zone.
const syncLocation = DocumentLocation(handle: 'memory:sync', label: 'Synced');

/// An open [DocumentSession] over [FakeDocumentDirectory], plus the second
/// device: [writeAsOtherDevice] is its own repository over the same store,
/// exactly how another machine's save arrives through a sync client.
final class SyncHarness {
  SyncHarness._(this.session, this.directory, this.locationPreference);

  final DocumentSession session;
  final FakeDocumentDirectory directory;
  final DocumentLocationPreference locationPreference;

  static Future<SyncHarness> open({
    DateTime Function()? clock,
    String deviceId = 'device-a',
  }) async {
    final directory = FakeDocumentDirectory();
    final preference = await DocumentLocationPreference.load();
    await preference.set(syncLocation);
    final session = DocumentSession(
      directory: directory,
      locationPreference: preference,
      clock: clock,
      deviceId: deviceId,
    );
    await session.open();
    expect(session.status, SessionStatus.ready, reason: 'harness must open');
    return SyncHarness._(session, directory, preference);
  }

  MemoryDocumentStore get store => directory.storeAt(syncLocation);

  Future<void> writeAsOtherDevice(
    CirrhyDocument Function(CirrhyDocument doc) change,
  ) async {
    final repo = DocumentRepository(store: directory.storeAt(syncLocation));
    final theirs = await repo.load();
    await repo.save(change(theirs));
  }
}

/// A stopped half-hour entry, for external writes.
TimeEntry entryAt(String id, DateTime start, {String? description}) =>
    TimeEntry(
      id: id,
      modified: start,
      start: start,
      stop: start.add(const Duration(minutes: 30)),
      projectId: null,
      locationChanged: start,
      description: description ?? id,
    );

/// A running timer another device left behind.
RunningTimer foreignTimerAt(
  String deviceId,
  DateTime startedAt, {
  String description = '',
}) => RunningTimer(
  deviceId: deviceId,
  modified: startedAt,
  startedAt: startedAt,
  description: description,
);

/// Retires the snackbar currently showing: entrance animation, display
/// duration, exit animation, removal. The auto-dismiss timer only starts once
/// the entrance completes, so a single long pump is not enough — the pumps
/// must walk the snackbar through its phases in order.
Future<void> drainSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Pumps the shell around the harness's session.
///
/// [withRecovery] hands the shell the directory and location preference the
/// A3 dialog needs; tests that want the folder-unreachable state *without*
/// the dialog in the way pass false.
Future<void> pumpSyncShell(
  WidgetTester tester,
  SyncHarness harness, {
  Locale locale = const Locale('en'),
  bool withRecovery = true,
}) => tester.pumpWidget(
  MaterialApp(
    theme: cirrhyLightTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: AppShell(
      session: harness.session,
      directory: withRecovery ? harness.directory : null,
      locationPreference: withRecovery ? harness.locationPreference : null,
    ),
  ),
);
