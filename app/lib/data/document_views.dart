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

/// Pure read-side helpers over [CirrhyDocument] — no Flutter imports, so they
/// are as cheaply unit-testable as the engine itself and reusable by every
/// screen that needs to answer the same questions about the document.
library;

import 'package:cirrhy_merge/cirrhy_merge.dart';

/// Whether [record] should be treated as archived for picker and list
/// purposes: its own `archived` flag, or that of any ancestor in the
/// client → project → task chain.
///
/// This is the one place that rule lives. A task whose own flag is false but
/// whose project (or that project's client) is archived is still effectively
/// archived — hiding a client should hide everything under it without
/// requiring every descendant to be flagged individually.
bool isEffectivelyArchived(CirrhyDocument doc, CirrhyRecord record) {
  return switch (record) {
    Client c => c.archived,
    Project p => p.archived || _clientArchived(doc, p.clientId),
    Task t => t.archived || _projectArchived(doc, t.projectId),
    _ => false,
  };
}

bool _clientArchived(CirrhyDocument doc, String? clientId) {
  if (clientId == null) return false;
  final client = doc.clients[clientId];
  return client != null && isEffectivelyArchived(doc, client);
}

bool _projectArchived(CirrhyDocument doc, String? projectId) {
  if (projectId == null) return false;
  final project = doc.projects[projectId];
  return project != null && isEffectivelyArchived(doc, project);
}

/// Sums the duration of closed entries (`stop != null`) matching the given
/// filters, in the entry's *local* start time.
///
/// The filters are checked in order of specificity: [taskId] alone, then
/// [projectId] alone, then [clientId] resolved through the entry's project —
/// each ignores the looser filters below it once it applies. Passing none of
/// the three sums every closed entry in the window.
///
/// [from] and [to] bound a half-open interval `[from, to)` on the entry's
/// local start time — half-open so a report ending exactly at a month
/// boundary never double-counts the instant that starts the next one.
Duration totalFor(
  CirrhyDocument doc, {
  String? clientId,
  String? projectId,
  String? taskId,
  DateTime? from,
  DateTime? to,
}) {
  var total = Duration.zero;
  for (final entry in doc.entries.values) {
    final stop = entry.stop;
    if (stop == null) continue;

    if (taskId != null) {
      if (entry.taskId != taskId) continue;
    } else if (projectId != null) {
      if (entry.projectId != projectId) continue;
    } else if (clientId != null) {
      final project = entry.projectId == null
          ? null
          : doc.projects[entry.projectId];
      if (project?.clientId != clientId) continue;
    }

    final start = entry.start.toLocal();
    if (from != null && start.isBefore(from)) continue;
    if (to != null && !start.isBefore(to)) continue;

    total += stop.difference(entry.start);
  }
  return total;
}

/// The closed entries the reports screen should count: `stop != null`, local
/// start inside the half-open `[from, to)` window, and matching every filter
/// axis that is switched on.
///
/// The axes **AND** with each other and each is a set-membership test, so an
/// empty set means "no filter on this axis" rather than "match nothing".
/// Selecting a client therefore does not implicitly select its projects: the
/// client axis is checked against the entry's own project's client, so an
/// entry with no project can never match a non-empty [clientIds].
///
/// Deliberately not folded into [totalFor], which answers a different
/// question — one entity at a time, most specific filter wins. Here every
/// axis must be checked, because that is what the filter sheet promises.
///
/// The result is sorted newest-first, matching `entriesByRecency`, so the
/// entries view can group it without re-sorting.
List<TimeEntry> entriesInRange(
  CirrhyDocument doc, {
  DateTime? from,
  DateTime? to,
  Set<String> clientIds = const {},
  Set<String> projectIds = const {},
  Set<String> taskIds = const {},
  bool billableOnly = false,
}) {
  final matched = <TimeEntry>[];
  for (final entry in doc.entries.values) {
    // An open entry has no duration anybody recorded yet; §3.6 keeps the
    // running timer out of the totals, and so does every report.
    if (entry.stop == null) continue;

    final start = entry.start.toLocal();
    if (from != null && start.isBefore(from)) continue;
    if (to != null && !start.isBefore(to)) continue;

    if (billableOnly && !entry.billable) continue;
    if (projectIds.isNotEmpty && !projectIds.contains(entry.projectId)) {
      continue;
    }
    if (taskIds.isNotEmpty && !taskIds.contains(entry.taskId)) continue;
    if (clientIds.isNotEmpty) {
      final project = entry.projectId == null
          ? null
          : doc.projects[entry.projectId];
      final clientId = project?.clientId;
      if (clientId == null || !clientIds.contains(clientId)) continue;
    }

    matched.add(entry);
  }
  matched.sort((a, b) => b.start.compareTo(a.start));
  return matched;
}

/// The local calendar day [instant] falls on, as that day's midnight.
///
/// The one place the "which day is this entry on" rule lives: the *local*
/// day of the entry's **start**. An entry that runs 23:30 → 00:30 belongs to
/// the day it began, not the one it ended in — splitting it across two days
/// would invent two intervals nobody tracked.
DateTime localDay(DateTime instant) {
  final local = instant.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Total duration of [entries]. Open entries contribute nothing, so this is
/// safe on any list, not just one [entriesInRange] produced.
Duration sumOf(Iterable<TimeEntry> entries) {
  var total = Duration.zero;
  for (final entry in entries) {
    total += entry.duration ?? Duration.zero;
  }
  return total;
}

/// Per-local-day totals, keyed by [localDay]. Days with nothing on them are
/// simply absent — the chart enumerates the window's days itself, because it
/// has to draw a stub for the empty ones.
Map<DateTime, Duration> dailyTotals(Iterable<TimeEntry> entries) {
  final totals = <DateTime, Duration>{};
  for (final entry in entries) {
    final day = localDay(entry.start);
    totals[day] =
        (totals[day] ?? Duration.zero) + (entry.duration ?? Duration.zero);
  }
  return totals;
}

/// Per-project totals, keyed by project id. The `null` key collects entries
/// that belong to no project at all, which the "by project" list shows under
/// its own heading rather than dropping.
Map<String?, Duration> projectTotals(Iterable<TimeEntry> entries) {
  final totals = <String?, Duration>{};
  for (final entry in entries) {
    final id = entry.projectId;
    totals[id] =
        (totals[id] ?? Duration.zero) + (entry.duration ?? Duration.zero);
  }
  return totals;
}

/// The half-open `[from, to)` window for the local calendar month containing
/// [now] — the "this month" reports and project/client cards show.
///
/// Local, not UTC: a moment just before midnight local time on the last day
/// of the month can already be the next UTC day, and the reverse near the
/// start of a month. Bounding on the local calendar is what keeps "this
/// month" meaning the month the user is actually in.
(DateTime from, DateTime to) currentMonthWindow(DateTime now) {
  final local = now.toLocal();
  final from = DateTime(local.year, local.month);
  final to = local.month == 12
      ? DateTime(local.year + 1, 1)
      : DateTime(local.year, local.month + 1);
  return (from, to);
}
