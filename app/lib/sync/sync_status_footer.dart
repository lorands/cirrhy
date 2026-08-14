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
import 'package:intl/intl.dart';

import '../data/document_session.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';

/// The desktop rail's sync-status line (G1): a dot and a caption at the
/// bottom of the rail, visibly surfacing sync state instead of pretending
/// sync is instant (§4.4).
///
/// Three honest states, nothing invented: the time of the last successful
/// re-read-and-merge, a warning while the folder is unreachable, and nothing
/// at all before the first refresh — the session opening is not a sync and is
/// not dressed up as one.
class SyncStatusFooter extends StatefulWidget {
  const SyncStatusFooter({super.key, required this.session});

  /// Null hides the footer entirely — a shell built without storage has no
  /// sync state to report.
  final DocumentSession? session;

  @override
  State<SyncStatusFooter> createState() => _SyncStatusFooterState();
}

class _SyncStatusFooterState extends State<SyncStatusFooter> {
  @override
  void initState() {
    super.initState();
    widget.session?.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(covariant SyncStatusFooter oldWidget) {
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

    return Container(
      key: const Key('railSyncFooter'),
      padding: const EdgeInsets.only(top: Space.x4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
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
      ),
    );
  }
}
