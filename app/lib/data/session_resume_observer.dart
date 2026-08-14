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

/// Refreshes the session whenever the app returns to the foreground.
///
/// DESIGN.md §4.4: nothing notifies us that a sync client rewrote the file
/// while the app was backgrounded, so the app has to ask — re-read, hash-
/// compare, merge — on every resume. Wraps the shell; renders nothing itself.
class SessionResumeObserver extends StatefulWidget {
  const SessionResumeObserver({
    super.key,
    required this.session,
    required this.child,
  });

  final DocumentSession session;
  final Widget child;

  @override
  State<SessionResumeObserver> createState() => _SessionResumeObserverState();
}

class _SessionResumeObserverState extends State<SessionResumeObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Fire-and-forget: refresh reports its outcome through the session's
    // status and lastError, which the screens already listen to.
    if (state == AppLifecycleState.resumed) unawaited(widget.session.refresh());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
