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

import 'package:flutter/widgets.dart';

import 'document_session.dart';

/// Keeps the session in step with the file for as long as the app is in front.
///
/// DESIGN.md §4.4: nothing notifies us that a sync client rewrote the file, so
/// the app has to ask — re-read, hash-compare, merge. This used to ask exactly
/// once, on resume, and that is the one read least likely to be the fresh one.
/// A cloud provider only starts fetching the new version when something touches
/// the folder, and finishes seconds later; by then our single read has been and
/// gone, and nothing looks again until the next resume. Found on iOS against a
/// Dropbox folder, where the file could sit days out of date while the app
/// insisted it was synced.
///
/// So the reads bunch up right after coming forward — [settling] — and then
/// settle to [steady] for as long as the app stays there, which also covers the
/// case the resume-only version could never see: another device writing while
/// this one is sitting open on the timer screen.
///
/// Every one of them is the same cheap ask. An unchanged file costs one read
/// and a hash compare and stops there (`DocumentRepository.refresh`); only a
/// file that actually differs is decoded and merged.
///
/// Wraps the shell; renders nothing itself.
class SessionRefresher extends StatefulWidget {
  const SessionRefresher({
    super.key,
    required this.session,
    required this.child,
  });

  final DocumentSession session;
  final Widget child;

  /// How long after coming forward each of the first few reads happens.
  ///
  /// Bunched because the provider's fetch is what we are waiting out, not the
  /// user: the first read catches a folder that was already up to date, and
  /// the rest catch one that was not.
  static const settling = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
  ];

  /// The interval the schedule settles into once [settling] is exhausted, and
  /// holds until the app leaves the foreground.
  static const steady = Duration(minutes: 1);

  @override
  State<SessionRefresher> createState() => _SessionRefresherState();
}

class _SessionRefresherState extends State<SessionRefresher>
    with WidgetsBindingObserver {
  Timer? _next;

  /// How far into [SessionRefresher.settling] the current run is. Reset by
  /// every resume, so each return to the app gets the full burst.
  int _step = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A cold start gets no lifecycle callback — it is already resumed — so the
    // schedule starts here rather than waiting for a state change that has
    // already happened. Null is the state before the engine has reported one,
    // which is the ordinary case at startup.
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) _start();
  }

  @override
  void didUpdateWidget(covariant SessionRefresher oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different session is a different file; the schedule belongs to the one
    // being watched now.
    if (oldWidget.session != widget.session) _start();
  }

  @override
  void dispose() {
    _next?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fire-and-forget: refresh reports its outcome through the session's
      // status and lastError, which the screens already listen to.
      unawaited(widget.session.refresh());
      _start();
    } else {
      // Nothing behind the app is worth a file read: the document is only
      // looked at when someone can see it, and a backgrounded poll would be
      // battery spent on an answer nobody reads.
      _next?.cancel();
      _next = null;
    }
  }

  void _start() {
    _step = 0;
    _schedule();
  }

  void _schedule() {
    _next?.cancel();
    final settling = SessionRefresher.settling;
    final delay = _step < settling.length
        ? settling[_step]
        : SessionRefresher.steady;
    _next = Timer(delay, () {
      _step++;
      unawaited(widget.session.refresh());
      _schedule();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
