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

import 'dart:math';

/// Generates a RFC 4122 version 4 UUID.
///
/// Hand-rolled rather than pulled from a package: the engine is meant to stay
/// dependency-light, and this is the only identifier primitive it needs.
String uuidV4() {
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 10xx
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// A prior version of a record, demoted by a merge it lost.
///
/// DESIGN.md §3.4: the loser of last-write-wins is kept, not destroyed. This is
/// what makes LWW acceptable at all — a data-loss bug becomes a recoverable one.
final class RecordVersion implements Comparable<RecordVersion> {
  const RecordVersion({required this.modified, required this.fields});

  final DateTime modified;
  final Map<String, Object?> fields;

  @override
  int compareTo(RecordVersion other) => other.modified.compareTo(modified);

  @override
  bool operator ==(Object other) =>
      other is RecordVersion &&
      other.modified.isAtSameMomentAs(modified) &&
      _sameFields(other.fields, fields);

  @override
  int get hashCode => Object.hash(modified, fields.length);

  static bool _sameFields(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
    }
    return true;
  }
}

/// Base for every mergeable record.
///
/// DESIGN.md §3.1: stable UUID plus last-modified timestamp. Merge is a union
/// over UUIDs — never positional, never by array index.
abstract base class CirrhyRecord {
  const CirrhyRecord({
    required this.id,
    required this.modified,
    this.importSource,
    this.externalId,
    this.history = const [],
  });

  final String id;

  /// Always UTC. See DESIGN.md §8.4 — timezone handling is still open; the
  /// engine stores instants and leaves presentation to the app.
  final DateTime modified;

  /// Which import produced this record, or null for everything made by hand.
  ///
  /// DESIGN.md §10: a free string naming the migration (e.g. `kimai -
  /// truenas`). Traceability only — the merge never reads it, and nothing
  /// enforces anything about it. Its one job is making a botched import batch
  /// addressable after the fact: rollback is "tombstone every record whose
  /// [importSource] matches, re-import". Set once by the importer, carried
  /// verbatim through every subsequent edit, never cleared.
  final String? importSource;

  /// The imported record's identifier in its source system, or null.
  ///
  /// DESIGN.md §10: provenance, **not a merge key** — the record [id] is
  /// still a fresh UUID and the merge stays a union over UUIDs. Compound
  /// (importer's choice of encoding) when the source needs more than one
  /// value to name a record.
  final String? externalId;

  final List<RecordVersion> history;

  /// This record's own fields, excluding [history]. Used for history snapshots,
  /// serialization and the deterministic tie-break when two devices write in the same instant.
  Map<String, Object?> toFields();

  /// Returns a copy carrying [history] instead of its own.
  CirrhyRecord withHistory(List<RecordVersion> history);

  RecordVersion snapshot() =>
      RecordVersion(modified: modified, fields: toFields());
}

/// A record whose parent can change independently of its other fields.
///
/// DESIGN.md §3.5: KDBX carries `LocationChanged` separately from last-modified
/// so that relocating an item and editing it merge independently. Re-assigning
/// a time entry to another project is a distinct event from editing its times.
abstract base class RelocatableRecord extends CirrhyRecord {
  const RelocatableRecord({
    required super.id,
    required super.modified,
    required this.parentId,
    required this.locationChanged,
    super.importSource,
    super.externalId,
    super.history,
  });

  final String? parentId;
  final DateTime locationChanged;

  /// Returns a copy re-parented to [parentId] as of [locationChanged].
  RelocatableRecord withParent(String? parentId, DateTime locationChanged);
}

final class Client extends CirrhyRecord {
  const Client({
    required super.id,
    required super.modified,
    required this.name,
    this.archived = false,
    super.importSource,
    super.externalId,
    super.history,
  });

  final String name;
  final bool archived;

  @override
  Map<String, Object?> toFields() => {
    'name': name,
    'archived': archived,
    // Emitted only when set, here and in every other record type: hand-made
    // records carry no provenance and their serialized form should not grow
    // two null keys apiece for a feature that touched none of them.
    if (importSource != null) 'importSource': importSource,
    if (externalId != null) 'externalId': externalId,
  };

  @override
  Client withHistory(List<RecordVersion> history) => Client(
    id: id,
    modified: modified,
    name: name,
    archived: archived,
    importSource: importSource,
    externalId: externalId,
    history: history,
  );
}

final class Project extends RelocatableRecord {
  const Project({
    required super.id,
    required super.modified,
    required this.name,
    required String? clientId,
    required super.locationChanged,
    this.color,
    this.billable = false,
    this.archived = false,
    super.importSource,
    super.externalId,
    super.history,
  }) : super(parentId: clientId);

  final String name;
  final String? color;
  final bool billable;
  final bool archived;

  String? get clientId => parentId;

  @override
  Map<String, Object?> toFields() => {
    'name': name,
    'clientId': clientId,
    'color': color,
    'billable': billable,
    'archived': archived,
    if (importSource != null) 'importSource': importSource,
    if (externalId != null) 'externalId': externalId,
  };

  @override
  Project withHistory(List<RecordVersion> history) => _copy(history: history);

  @override
  Project withParent(String? parentId, DateTime locationChanged) =>
      _copy(clientId: parentId, locationChanged: locationChanged);

  Project _copy({
    String? clientId,
    DateTime? locationChanged,
    List<RecordVersion>? history,
  }) => Project(
    id: id,
    modified: modified,
    name: name,
    clientId: clientId ?? this.clientId,
    locationChanged: locationChanged ?? this.locationChanged,
    color: color,
    billable: billable,
    archived: archived,
    importSource: importSource,
    externalId: externalId,
    history: history ?? this.history,
  );
}

final class Task extends RelocatableRecord {
  const Task({
    required super.id,
    required super.modified,
    required this.name,
    required String? projectId,
    required super.locationChanged,
    this.archived = false,
    super.importSource,
    super.externalId,
    super.history,
  }) : super(parentId: projectId);

  final String name;
  final bool archived;

  String? get projectId => parentId;

  @override
  Map<String, Object?> toFields() => {
    'name': name,
    'projectId': projectId,
    'archived': archived,
    if (importSource != null) 'importSource': importSource,
    if (externalId != null) 'externalId': externalId,
  };

  @override
  Task withHistory(List<RecordVersion> history) => _copy(history: history);

  @override
  Task withParent(String? parentId, DateTime locationChanged) =>
      _copy(projectId: parentId, locationChanged: locationChanged);

  Task _copy({
    String? projectId,
    DateTime? locationChanged,
    List<RecordVersion>? history,
  }) => Task(
    id: id,
    modified: modified,
    name: name,
    projectId: projectId ?? this.projectId,
    locationChanged: locationChanged ?? this.locationChanged,
    archived: archived,
    importSource: importSource,
    externalId: externalId,
    history: history ?? this.history,
  );
}

/// A logged interval.
///
/// DESIGN.md §3.1: [start] and [stop] merge as a *unit*. They are never
/// field-merged across devices — taking a start from one and a stop from the
/// other produces a duration nobody recorded.
final class TimeEntry extends RelocatableRecord {
  const TimeEntry({
    required super.id,
    required super.modified,
    required this.start,
    required this.stop,
    required String? projectId,
    required super.locationChanged,
    this.taskId,
    this.description = '',
    this.billable = false,
    super.importSource,
    super.externalId,
    super.history,
  }) : super(parentId: projectId);

  final DateTime start;

  /// `null` means the entry is still open. A stopped entry is effectively
  /// immutable, which is why genuine conflicts here are rare (DESIGN.md §3.6).
  final DateTime? stop;

  final String? taskId;
  final String description;
  final bool billable;

  String? get projectId => parentId;

  Duration? get duration => stop?.difference(start);

  @override
  Map<String, Object?> toFields() => {
    'start': start.toIso8601String(),
    'stop': stop?.toIso8601String(),
    'projectId': projectId,
    'taskId': taskId,
    'description': description,
    'billable': billable,
    if (importSource != null) 'importSource': importSource,
    if (externalId != null) 'externalId': externalId,
  };

  @override
  TimeEntry withHistory(List<RecordVersion> history) => _copy(history: history);

  @override
  TimeEntry withParent(String? parentId, DateTime locationChanged) =>
      _copy(projectId: parentId, locationChanged: locationChanged);

  TimeEntry _copy({
    String? projectId,
    DateTime? locationChanged,
    List<RecordVersion>? history,
  }) => TimeEntry(
    id: id,
    modified: modified,
    start: start,
    stop: stop,
    projectId: projectId ?? this.projectId,
    locationChanged: locationChanged ?? this.locationChanged,
    taskId: taskId,
    description: description,
    billable: billable,
    importSource: importSource,
    externalId: externalId,
    history: history ?? this.history,
  );
}

/// A timer running on one device.
///
/// DESIGN.md §3.6: the running timer is a mutable singleton and last-write-wins
/// is *wrong* for it — LWW silently discards a tracked interval, which is
/// precisely the data the app exists to protect. So it is keyed by device: two
/// devices merge into two open timers the UI surfaces for reconciliation.
final class RunningTimer extends CirrhyRecord {
  const RunningTimer({
    required this.deviceId,
    required super.modified,
    required this.startedAt,
    this.projectId,
    this.taskId,
    this.description = '',
    super.importSource,
    super.externalId,
    super.history,
  }) : super(id: deviceId);

  final String deviceId;
  final DateTime startedAt;
  final String? projectId;
  final String? taskId;
  final String description;

  @override
  Map<String, Object?> toFields() => {
    'deviceId': deviceId,
    'startedAt': startedAt.toIso8601String(),
    'projectId': projectId,
    'taskId': taskId,
    'description': description,
    if (importSource != null) 'importSource': importSource,
    if (externalId != null) 'externalId': externalId,
  };

  @override
  RunningTimer withHistory(List<RecordVersion> history) => RunningTimer(
    deviceId: deviceId,
    modified: modified,
    startedAt: startedAt,
    projectId: projectId,
    taskId: taskId,
    description: description,
    importSource: importSource,
    externalId: externalId,
    history: history,
  );

  /// Closes this timer into a logged entry.
  ///
  /// Provenance deliberately does not flow through: the entry records work
  /// tracked here and now, whatever a (spec-violating) importer may have
  /// stamped on the timer it came from.
  TimeEntry stopAt(DateTime when, {String? id}) => TimeEntry(
    id: id ?? uuidV4(),
    modified: when,
    start: startedAt,
    stop: when,
    projectId: projectId,
    locationChanged: when,
    taskId: taskId,
    description: description,
  );
}

/// A recorded deletion.
///
/// DESIGN.md §3.3: without tombstones every merge silently *resurrects*
/// whatever the peer deleted, and the bug is invisible until days later.
final class Tombstone {
  const Tombstone({required this.id, required this.deletedAt});

  final String id;
  final DateTime deletedAt;

  Map<String, Object?> toFields() => {
    'id': id,
    'deletedAt': deletedAt.toIso8601String(),
  };
}
