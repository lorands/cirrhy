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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/document_session.dart';
import '../l10n/generated/app_localizations.dart';

/// Mirrors "a timer is running on *this* device" onto the app's icon.
///
/// The screens already show the running timer; this is for every moment the
/// app is not the thing being looked at — the badge answers "did I leave the
/// timer on?" from the dock, taskbar or home screen. Each platform renders it
/// in the shape its OS offers (a dock-icon swap, a taskbar overlay, a
/// launcher-badge notification); the Dart side only states the fact.
///
/// [DocumentSession.myTimer] is deliberately the only trigger. Foreign timers
/// are another device's business — F1 surfaces them in the app — and badging
/// for them here would make the icon cry wolf on every synced laptop.
class TimerBadge {
  TimerBadge({@visibleForTesting MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.lorands.cirrhy/badge');

  final MethodChannel _channel;

  DocumentSession? _session;
  AppLocalizations? _l10n;

  /// The last payload pushed, so session notifies that change nothing —
  /// most of them — do not become channel chatter.
  Object? _pushed;

  /// Starts following [session], replacing whatever was followed before.
  void attach(DocumentSession? session) {
    if (identical(session, _session)) return;
    _session?.removeListener(_sync);
    _session = session;
    session?.addListener(_sync);
    _sync();
  }

  /// Hands over the strings for the surfaces drawn outside Flutter — the
  /// Android notification and its channel. Safe to call every build; a
  /// same-language call changes nothing and pushes nothing.
  void localize(AppLocalizations l10n) {
    _l10n = l10n;
    _sync();
  }

  void dispose() {
    _session?.removeListener(_sync);
    _session = null;
  }

  void _sync() {
    // Waits for both halves: without strings an Android notification would
    // show placeholder text. Both arrive within the shell's first build.
    final l10n = _l10n;
    if (l10n == null) return;

    final session = _session;
    final timer = session?.myTimer;

    final Object payload;
    if (session == null || timer == null) {
      payload = const {'running': false};
    } else {
      final document = session.document;
      // The most specific label available, the same precedence the timer
      // screen leads with: what you typed, else the task, else the project.
      final subject = timer.description.isNotEmpty
          ? timer.description
          : document.tasks[timer.taskId]?.name ??
                document.projects[timer.projectId]?.name;
      payload = {
        'running': true,
        'startedAt': timer.startedAt.toUtc().millisecondsSinceEpoch,
        'title': l10n.timerBadgeTitle,
        'subject': ?subject,
        'channelName': l10n.timerBadgeChannelName,
      };
    }

    if (mapEquals(_asMap(payload), _asMap(_pushed))) return;
    _pushed = payload;

    _channel.invokeMethod<void>('setTimer', payload).catchError((Object e) {
      // A platform without the handler (tests, an untested target) simply
      // has no badge; the timer itself is not affected.
      assert(e is MissingPluginException, 'badge channel failed: $e');
    });
  }

  Map<String, Object?>? _asMap(Object? payload) =>
      payload == null ? null : (payload as Map).cast<String, Object?>();
}
