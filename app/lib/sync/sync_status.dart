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

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/document_session.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';

/// Where the line is being shown, which is the only thing that differs between
/// the two: the frame around it.
enum SyncStatusPlacement {
  /// The bottom of the desktop rail, where the G1 mockup puts it.
  rail,

  /// A strip above the narrow layout's tab bar — the same information in the
  /// same place in the frame, for the layout that has no rail. It was missing
  /// here for as long as the rail had it, which meant a phone gave the user no
  /// way at all to see whether the file was being re-read (§4.4 asks for sync
  /// state surfaced, and a phone is where sync goes wrong).
  bar,
}

/// The sync-status line: a dot, a caption, and a tap that re-reads the file.
///
/// Three honest states, nothing invented: the time of the last successful
/// re-read-and-merge, a warning while the folder is unreachable, and nothing at
/// all before the first refresh — the session opening is not a sync and is not
/// dressed up as one.
///
/// Tapping it refreshes. The schedule (`SessionRefresher`) is what normally
/// keeps the document current; this is the manual override for when a sync
/// client is being slow and the user knows something is waiting, and it doubles
/// as the answer to "is this thing even trying?" — the caption's clock moves.
class SyncStatus extends StatefulWidget {
  const SyncStatus({
    super.key,
    required this.session,
    this.placement = SyncStatusPlacement.rail,
  });

  /// Null hides the line entirely — a shell built without storage has no sync
  /// state to report.
  final DocumentSession? session;

  final SyncStatusPlacement placement;

  @override
  State<SyncStatus> createState() => _SyncStatusState();
}

class _SyncStatusState extends State<SyncStatus> {
  @override
  void initState() {
    super.initState();
    widget.session?.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(covariant SyncStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session?.removeListener(_onSessionChanged);
      widget.session?.addListener(_onSessionChanged);
    }
  }

  @override
  void dispose() {
    widget.session?.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (session == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);

    final (Color dot, String message)? line = switch (session.status) {
      SessionStatus.unavailable => (
        colors.warning,
        l10n.folderUnreachableShort,
      ),
      SessionStatus.ready when session.lastRefreshed != null => (
        colors.running,
        l10n.syncedAtTime(
          DateFormat.Hm(
            l10n.localeName,
          ).format(session.lastRefreshed!.toLocal()),
        ),
      ),
      _ => null,
    };
    if (line == null) return const SizedBox.shrink();

    final row = Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: line.$1, shape: BoxShape.circle),
        ),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Text(
            line.$2,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    // Material(transparency) rather than a bare InkWell: neither host wraps
    // this in a Material of its own, and InkWell alone throws without one.
    final tappable = Tooltip(
      message: l10n.syncRefreshNow,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: () => unawaited(session.refresh()),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.x2,
              vertical: Space.x2,
            ),
            child: row,
          ),
        ),
      ),
    );

    return switch (widget.placement) {
      SyncStatusPlacement.rail => Container(
        key: const Key('railSyncFooter'),
        padding: const EdgeInsets.only(top: Space.x2),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: tappable,
      ),
      SyncStatusPlacement.bar => Container(
        key: const Key('barSyncStatus'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: Space.x2),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: tappable,
      ),
    };
  }
}
