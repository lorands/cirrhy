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

import 'dart:ui' show Locale;

import 'package:cirrhy/l10n/generated/app_localizations.dart';
import 'package:cirrhy/timer/timer_badge.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sync/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.lorands.cirrhy/badge');
  late List<Map<Object?, Object?>> pushed;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pushed = [];
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'setTimer');
          pushed.add(call.arguments as Map<Object?, Object?>);
          return null;
        });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// invokeMethod answers through the messenger asynchronously; one microtask
  /// drain is what lets the recorded call land in [pushed].
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  TimerBadge badge() =>
      TimerBadge(channel: channel)
        ..localize(lookupAppLocalizations(const Locale('en')));

  test('mirrors start and stop, and stays quiet in between', () async {
    final harness = await SyncHarness.open();
    final b = badge()..attach(harness.session);
    await settle();
    expect(pushed, [
      {'running': false},
    ]);

    await harness.session.startTimer(description: 'Deep work');
    await settle();
    expect(pushed, hasLength(2));
    final shown = pushed.last;
    expect(shown['running'], isTrue);
    expect(shown['title'], 'Timer running');
    expect(shown['subject'], 'Deep work');
    expect(shown['startedAt'], isA<int>());
    expect(shown['channelName'], 'Running timer');

    // A notify that changes nothing about the timer must not chatter.
    await harness.session.refresh();
    await settle();
    expect(pushed, hasLength(2));

    await harness.session.stopTimer();
    await settle();
    expect(pushed, hasLength(3));
    expect(pushed.last, {'running': false});

    b.dispose();
  });

  test('falls back to the task name when the description is empty', () async {
    final harness = await SyncHarness.open();
    final start = DateTime.utc(2026, 8, 15, 9);
    await harness.session.put(
      Task(
        id: 'task-1',
        modified: start,
        name: 'Weekly report',
        projectId: null,
        locationChanged: start,
      ),
    );

    final b = badge()..attach(harness.session);
    await harness.session.startTimer(taskId: 'task-1');
    await settle();
    expect(pushed.last['subject'], 'Weekly report');
    b.dispose();
  });

  test('a disposed badge stops reporting', () async {
    final harness = await SyncHarness.open();
    final b = badge()..attach(harness.session);
    await settle();
    b.dispose();

    await harness.session.startTimer(description: 'after dispose');
    await settle();
    expect(pushed, [
      {'running': false},
    ]);
  });
}
