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

import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/document_session.dart';
import '../l10n/duration_format.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/entity_chip.dart';

/// F1 — "Two timers were running": the reconciliation prompt DESIGN.md §3.6
/// demands whenever a merge brings in another device's running timer.
///
/// The per-device timer model means nothing here is a conflict to resolve —
/// both intervals already exist and both are already safe. This section only
/// *tells* the user that, and offers the two honest actions: leave both
/// running, or stop the other device's timer into a logged entry. It sits on
/// the timer screen between the timer card and the entry list, and disappears
/// once the user acknowledges or the foreign timers stop.
///
/// The design names the other device ("Work laptop"); the document only
/// carries an opaque device id, so the cards say "Another device" instead of
/// inventing a name.
class ForeignTimersSection extends StatefulWidget {
  const ForeignTimersSection({
    super.key,
    required this.session,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final DocumentSession session;

  /// Where the ticking elapsed readouts read "now" from — injectable for the
  /// same reason as `TimerScreen.clock`, and handed down from it.
  final DateTime Function() clock;

  @override
  State<ForeignTimersSection> createState() => _ForeignTimersSectionState();
}

class _ForeignTimersSectionState extends State<ForeignTimersSection> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    // Same shape as the running card's ticker: rebuild every second and
    // recompute elapsed from the clock, so nothing accumulates or drifts.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final now = widget.clock().toUtc();
    final myTimer = session.myTimer;
    final foreign = session.foreignTimers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _WarningBanner(),
        if (myTimer != null) ...[
          const SizedBox(height: Space.x4),
          _DeviceTimerCard(
            key: const Key('thisDeviceTimerCard'),
            session: session,
            timer: myTimer,
            icon: Icons.smartphone,
            deviceLabel: l10n.thisDeviceLabel,
            elapsed: now.difference(myTimer.startedAt),
            caption: l10n.timerRunning,
            captionColor: colors.running,
            showRunningDot: true,
          ),
        ],
        for (final timer in foreign) ...[
          const SizedBox(height: Space.x4),
          _DeviceTimerCard(
            key: Key('foreignTimerCard-${timer.deviceId}'),
            session: session,
            timer: timer,
            icon: Icons.laptop,
            deviceLabel: l10n.otherDeviceLabel,
            elapsed: now.difference(timer.startedAt),
            caption: l10n.startedAtTime(
              DateFormat.Hm(l10n.localeName).format(timer.startedAt.toLocal()),
            ),
            captionColor: colors.textMuted,
            showRunningDot: false,
          ),
        ],
        const SizedBox(height: Space.x5),
        FilledButton(
          key: const Key('keepBothButton'),
          onPressed: session.acknowledgeForeignTimers,
          child: Text(l10n.keepBothAction),
        ),
        // One outlined stop per foreign timer, in card order. With a single
        // foreign timer — the overwhelmingly common case — this matches the
        // mockup exactly; with several, order is what ties button to card.
        for (final timer in foreign) ...[
          const SizedBox(height: Space.x3),
          OutlinedButton(
            key: Key('stopForeignButton-${timer.deviceId}'),
            onPressed: () => session.stopForeignTimer(timer.deviceId),
            child: Text(l10n.stopForeignAction),
          ),
        ],
        const SizedBox(height: Space.x4),
        Text(
          l10n.twoTimersFootnote,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Container(
      key: const Key('foreignTimersBanner'),
      padding: const EdgeInsets.all(Space.x4),
      decoration: BoxDecoration(
        color: colors.warningSubtle,
        borderRadius: BorderRadius.circular(Radii.lg),
        // A tint of the warning colour, not the full-strength stroke — the
        // banner informs, it does not alarm.
        border: Border.all(color: colors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, size: 20, color: colors.warning),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.twoTimersTitle,
                  style: text.labelLarge?.copyWith(color: colors.warning),
                ),
                const SizedBox(height: Space.x1),
                Text(
                  l10n.twoTimersBody,
                  style: text.labelSmall?.copyWith(color: colors.warning),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One side of the reconciliation: a device's running timer, ticking.
class _DeviceTimerCard extends StatelessWidget {
  const _DeviceTimerCard({
    super.key,
    required this.session,
    required this.timer,
    required this.icon,
    required this.deviceLabel,
    required this.elapsed,
    required this.caption,
    required this.captionColor,
    required this.showRunningDot,
  });

  final DocumentSession session;
  final RunningTimer timer;
  final IconData icon;
  final String deviceLabel;
  final Duration elapsed;
  final String caption;
  final Color captionColor;
  final bool showRunningDot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final project = session.projectById(timer.projectId);
    final client = session.clientById(project?.clientId);
    final hasDescription = timer.description.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xl),
        boxShadow: Elevation.level1,
      ),
      child: Container(
        padding: const EdgeInsets.all(Space.x5),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.xl),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: colors.textMuted),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(
                    deviceLabel,
                    style: text.labelSmall?.copyWith(
                      color: colors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (showRunningDot)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.running,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.x3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasDescription
                            ? timer.description
                            : l10n.timerNoDescription,
                        style: hasDescription
                            ? text.bodyLarge
                            : text.bodyLarge?.copyWith(color: colors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (project != null) ...[
                        const SizedBox(height: Space.x2),
                        ProjectChip(project: project, client: client),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Space.x3),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatTimer(elapsed, l10n.localeName),
                      // The mockup draws this readout between the list's
                      // duration size and the big timer display; scale the
                      // duration style rather than mint a fourth mono token.
                      style: Type.duration.copyWith(
                        fontSize: 20,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: Space.x1),
                    Text(
                      caption,
                      style: text.labelSmall?.copyWith(color: captionColor),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
