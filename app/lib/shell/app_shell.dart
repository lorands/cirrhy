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

import '../data/document_session.dart';
import '../data/session_refresher.dart';
import '../l10n/generated/app_localizations.dart';
import '../projects/projects_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/document_location_preference.dart';
import '../settings/locale_preference.dart';
import '../settings/settings_screen.dart';
import '../settings/theme_preference.dart';
import '../storage/document_directory.dart';
import '../sync/folder_unreachable_dialog.dart';
import '../sync/sync_status.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../timer/timer_badge.dart';
import '../timer/timer_screen.dart';
import 'watermark.dart';

const _markAsset = 'assets/logo/cirrhy-mark.png';

/// Below this width the rail gives way to a bottom tab bar. There is no
/// screen mockup between the two yet (§9), so this is a single, named
/// threshold rather than something guessed at in three different places.
const _wideBreakpoint = 900.0;

/// The four-destination navigation shell: Timer, Reports, Projects, Settings.
///
/// This replaces `_Placeholder` as the non-first-run screen. It takes exactly
/// what `SettingsScreen` needs, because the Settings destination is that
/// screen unchanged — reused, not re-implemented.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.localePreference,
    this.locationPreference,
    this.directory,
    this.themePreference,
    this.session,
  });

  /// Null only in tests that build the shell without the app's real
  /// dependencies. When any of the three is null the Settings destination
  /// renders empty, the same guard `_Placeholder` used to apply to its
  /// settings icon.
  final LocalePreference? localePreference;
  final DocumentLocationPreference? locationPreference;
  final DocumentDirectory? directory;

  /// Null in tests that do not exercise theming; the Settings destination
  /// simply hides its Appearance row, the same as a null [localePreference]
  /// hides the whole screen.
  final ThemePreference? themePreference;

  /// The open document. Null keeps the shell's original stub behaviour, so
  /// `const CirrhyApp()` tests still build without storage.
  final DocumentSession? session;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// The last refresh this shell has already reacted to, so one merge is
  /// announced exactly once however many notifies follow it.
  DateTime? _seenRefresh;

  /// The status as of the previous notify — the A3 dialog fires on the
  /// *transition* into unavailable, not on being there (§4.4 says prompt, not
  /// nag).
  SessionStatus? _seenStatus;

  bool _unavailableDialogOpen = false;

  /// The launcher-icon mirror of this device's running timer. Owned here
  /// because the shell is the one widget alive for the whole signed-in life
  /// of the app, on every platform.
  final TimerBadge _badge = TimerBadge();

  @override
  void initState() {
    super.initState();
    _attach(widget.session);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-runs when the locale changes, keeping the notification's strings in
    // the language the app shows.
    _badge.localize(AppLocalizations.of(context));
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session?.removeListener(_onSessionEvent);
      _attach(widget.session);
    }
  }

  @override
  void dispose() {
    _badge.dispose();
    widget.session?.removeListener(_onSessionEvent);
    super.dispose();
  }

  void _attach(DocumentSession? session) {
    // Baselines, not zeroes: a session handed over mid-life must not replay
    // its past — an old refresh is not news, and an already-unavailable
    // status is not a fresh transition.
    _seenRefresh = session?.lastRefreshed;
    _seenStatus = session?.status;
    session?.addListener(_onSessionEvent);
    _badge.attach(session);
  }

  void _onSessionEvent() {
    final session = widget.session;
    if (session == null || !mounted) return;

    final refreshed = session.lastRefreshed;
    if (refreshed != null && refreshed != _seenRefresh) {
      _seenRefresh = refreshed;
      if (session.lastRefreshNewRecords > 0) {
        _showMergeSnackBar(session.lastRefreshNewRecords);
      }
    }

    final status = session.status;
    final wasUnavailable = _seenStatus == SessionStatus.unavailable;
    _seenStatus = status;
    if (status == SessionStatus.unavailable && !wasUnavailable) {
      _showUnavailableDialog(session);
    }
  }

  /// F2: the merge made visible — sync state surfaced rather than pretended
  /// away (§4.4).
  void _showMergeSnackBar(int count) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.inverse,
        content: Row(
          children: [
            Icon(Icons.sync, size: 18, color: colors.textInverse),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Text(
                l10n.mergedChanges(count),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textInverse),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUnavailableDialog(DocumentSession session) {
    final directory = widget.directory;
    final locationPreference = widget.locationPreference;
    // Without the pieces the re-select flow needs there is nothing the dialog
    // could offer — the test shells that omit them get no dead-end dialog.
    if (directory == null || locationPreference == null) return;
    if (_unavailableDialogOpen) return;
    _unavailableDialogOpen = true;
    showFolderUnreachableDialog(
      context,
      session: session,
      directory: directory,
      locationPreference: locationPreference,
    ).whenComplete(() => _unavailableDialogOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final body = _shell(context);
    if (session == null) return body;
    // §4.4: nothing tells us the file changed underneath us, so the app keeps
    // asking for as long as it is in front — bunched right after a resume,
    // then steadily.
    return SessionRefresher(session: session, child: body);
  }

  Widget _shell(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final l10n = AppLocalizations.of(context);

    final items = [
      _NavItem(icon: Icons.schedule, label: l10n.tabTimer),
      _NavItem(icon: Icons.bar_chart, label: l10n.tabReports),
      _NavItem(icon: Icons.folder_outlined, label: l10n.tabProjects),
      _NavItem(icon: Icons.tune, label: l10n.tabSettings),
    ];

    void select(int index) => setState(() => _index = index);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _wideBreakpoint;

          return Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: colors.canvas)),
              // The one constant across every destination: it sits on the
              // canvas, under whichever tab is showing, and never moves as
              // tabs switch.
              Positioned.fill(child: CirrhyWatermark(alignEnd: wide)),
              Positioned.fill(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Rail(
                            items: items,
                            selectedIndex: _index,
                            onSelect: select,
                            session: widget.session,
                          ),
                          // The rail keeps its own side clear, so this is
                          // about the status bar over the content.
                          Expanded(
                            child: SafeArea(
                              left: false,
                              child: _content(_index),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          // Bottom is the bar's to keep clear, not the
                          // content's — the bar already extends under the
                          // home indicator.
                          Expanded(
                            child: SafeArea(
                              bottom: false,
                              child: _content(_index),
                            ),
                          ),
                          // The rail's footer, for the layout that has no
                          // rail: same information, same place in the frame,
                          // above the bar rather than below the destinations.
                          SyncStatus(
                            session: widget.session,
                            placement: SyncStatusPlacement.bar,
                          ),
                          _BottomBar(
                            items: items,
                            selectedIndex: _index,
                            onSelect: select,
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Every destination is built once and kept.
  ///
  /// This used to be a `switch` returning one screen, which meant switching
  /// tabs and switching back rebuilt the screen from scratch — a scrolled
  /// entry list jumped to the top, and the reports screen forgot which week
  /// it was showing. Those are `State`s worth keeping, and `IndexedStack` is
  /// what keeps them: all four stay mounted, only the selected one paints,
  /// and only the selected one hit-tests.
  ///
  /// The cost is that all four build eagerly at startup rather than on first
  /// visit. That is affordable here because every one of them reads the same
  /// already-open document and none does IO of its own.
  Widget _content(int index) {
    return IndexedStack(
      index: index,
      // Tight constraints for the visible child, matching what it got when
      // it was the sole occupant of the Expanded above.
      sizing: StackFit.expand,
      children: [
        TimerScreen(session: widget.session),
        ReportsScreen(session: widget.session),
        ProjectsScreen(session: widget.session),
        _settingsTab(),
      ],
    );
  }

  /// Reuses `SettingsScreen` outright rather than stubbing it, since the
  /// screen already exists and nothing about it changes by being hosted in a
  /// tab instead of behind an app-bar icon.
  Widget _settingsTab() {
    final locale = widget.localePreference;
    final location = widget.locationPreference;
    final directory = widget.directory;
    if (locale == null || location == null || directory == null) {
      return const SizedBox.shrink();
    }
    return SettingsScreen(
      localePreference: locale,
      locationPreference: location,
      directory: directory,
      themePreference: widget.themePreference,
      session: widget.session,
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// The narrow-layout destination bar.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// The bar's own height. The home-indicator inset is added to it rather
  /// than taken out of it — sizing the container to a flat 72 and then putting
  /// a `SafeArea` inside left the tabs 37px to lay out in on an iPhone, which
  /// is three short of what an icon over a label needs.
  static const double _height = 72;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    // The same source SafeArea reads, so the two always agree — notably when
    // the keyboard covers the indicator and the inset goes to zero.
    final inset = MediaQuery.paddingOf(context).bottom;

    return Container(
      height: _height + inset,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _BottomBarItem(
                    key: Key('navTab$i'),
                    item: items[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  const _BottomBarItem({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final color = selected ? colors.brand : colors.textMuted;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, size: 20, color: color),
          const SizedBox(height: Space.x1),
          Text(item.label, style: text.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// The wide-layout left rail.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.session,
  });

  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final DocumentSession? session;

  static const double _width = 220;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);

    return Container(
      width: _width,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x4,
            vertical: Space.x6,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(_markAsset, width: 28, height: 28),
                  const SizedBox(width: Space.x2),
                  Text(l10n.appTitle, style: text.headlineSmall),
                ],
              ),
              const SizedBox(height: Space.x8),
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x1),
                  child: _RailRow(
                    key: Key('navRail$i'),
                    item: items[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelect(i),
                  ),
                ),
              const Spacer(),
              // The reserved slot, filled: sync state where the desktop
              // mockup (G1) puts it, listening to the session on its own.
              SyncStatus(session: session),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  static const double _height = 44;

  @override
  Widget build(BuildContext context) {
    final colors = CirrhyTheme.of(context);
    final text = Theme.of(context).textTheme;
    final color = selected ? colors.brand : colors.textMuted;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Container(
          height: _height,
          padding: const EdgeInsets.symmetric(horizontal: Space.x3),
          decoration: BoxDecoration(
            color: selected ? colors.brandSubtle : null,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 20, color: color),
              const SizedBox(width: Space.x3),
              Text(item.label, style: text.bodyMedium?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
