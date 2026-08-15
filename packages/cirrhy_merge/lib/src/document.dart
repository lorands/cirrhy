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

import 'records.dart';

/// The whole document, loaded entirely into memory.
///
/// DESIGN.md §5: a whole-document format, not SQLite — WAL and journal sidecars
/// break the single-file promise, and whole-document is what the merge model
/// wants anyway. A heavy user produces a few thousand entries a year, so size
/// is not a concern.
final class CirrhyDocument {
  const CirrhyDocument({
    this.clients = const {},
    this.projects = const {},
    this.tasks = const {},
    this.entries = const {},
    this.runningTimers = const {},
    this.tombstones = const {},
  });

  const CirrhyDocument.empty() : this();

  /// Bumped only for changes the reader cannot infer. Readers must refuse a
  /// version they do not know rather than guess and write a lossy file back.
  ///
  /// v2 (2026-08-14): the §10 provenance fields, `importSource` and
  /// `externalId`. A v1 reader would not know to preserve them and would
  /// silently strip an import batch's addressability on its first write-back
  /// — exactly the lossy case this constant exists to refuse.
  static const int formatVersion = 2;

  final Map<String, Client> clients;
  final Map<String, Project> projects;
  final Map<String, Task> tasks;
  final Map<String, TimeEntry> entries;

  /// Keyed by device id, not a singleton. DESIGN.md §3.6.
  final Map<String, RunningTimer> runningTimers;

  final Map<String, Tombstone> tombstones;

  CirrhyDocument copyWith({
    Map<String, Client>? clients,
    Map<String, Project>? projects,
    Map<String, Task>? tasks,
    Map<String, TimeEntry>? entries,
    Map<String, RunningTimer>? runningTimers,
    Map<String, Tombstone>? tombstones,
  }) => CirrhyDocument(
    clients: clients ?? this.clients,
    projects: projects ?? this.projects,
    tasks: tasks ?? this.tasks,
    entries: entries ?? this.entries,
    runningTimers: runningTimers ?? this.runningTimers,
    tombstones: tombstones ?? this.tombstones,
  );

  /// Records a deletion rather than just applying one.
  ///
  /// DESIGN.md §3.3: dropping the record without a tombstone means the next
  /// merge resurrects it from the peer.
  CirrhyDocument delete(String id, DateTime at) => copyWith(
    clients: {...clients}..remove(id),
    projects: {...projects}..remove(id),
    tasks: {...tasks}..remove(id),
    entries: {...entries}..remove(id),
    runningTimers: {...runningTimers}..remove(id),
    tombstones: {
      ...tombstones,
      id: Tombstone(id: id, deletedAt: at),
    },
  );

  CirrhyDocument put(CirrhyRecord record) => switch (record) {
    final Client r => copyWith(clients: {...clients, r.id: r}),
    final Project r => copyWith(projects: {...projects, r.id: r}),
    final Task r => copyWith(tasks: {...tasks, r.id: r}),
    final TimeEntry r => copyWith(entries: {...entries, r.id: r}),
    final RunningTimer r => copyWith(
      runningTimers: {...runningTimers, r.deviceId: r},
    ),
    _ => throw ArgumentError('unknown record type: ${record.runtimeType}'),
  };

  /// Stops this device's timer and files the resulting entry.
  ///
  /// Removing the timer leaves a tombstone so a peer that still holds it does
  /// not hand it back on the next merge, restarting a timer the user stopped.
  CirrhyDocument stopTimer(String deviceId, DateTime at) {
    final timer = runningTimers[deviceId];
    if (timer == null) return this;
    return put(timer.stopAt(at)).delete(deviceId, at);
  }

  /// The entries a report or the main list would show, newest first.
  List<TimeEntry> entriesByRecency() =>
      entries.values.toList()..sort((a, b) => b.start.compareTo(a.start));

  /// Timers running on devices other than [deviceId].
  ///
  /// Non-empty means two devices tracked at once and the UI must surface a
  /// reconciliation prompt — never resolve it silently. DESIGN.md §3.6.
  List<RunningTimer> foreignTimers(String deviceId) =>
      runningTimers.values.where((t) => t.deviceId != deviceId).toList();

  int get recordCount =>
      clients.length +
      projects.length +
      tasks.length +
      entries.length +
      runningTimers.length;
}
