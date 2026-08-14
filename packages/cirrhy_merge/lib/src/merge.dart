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

import 'dart:convert';

import 'document.dart';
import 'records.dart';

/// How many prior versions to keep per record.
///
/// DESIGN.md §3.4: KeePass merges history without deleting from it, pruning
/// only by configured age/count limits. This is the count limit.
const int defaultHistoryLimit = 20;

/// Merges two documents into one.
///
/// The merge is a union over UUIDs where the newer last-modified wins and the
/// loser is demoted to history. It is **commutative** — `merge(a, b)` and
/// `merge(b, a)` produce the same document, including on timestamp ties — and
/// **idempotent**, so re-merging an already-merged document changes nothing.
/// Both properties are covered by tests; they are what make it safe to run this
/// on every save without knowing which side is "ours".
CirrhyDocument mergeDocuments(
  CirrhyDocument a,
  CirrhyDocument b, {
  int historyLimit = defaultHistoryLimit,
}) {
  final tombstones = _mergeTombstones(a.tombstones, b.tombstones);

  final clients = _mergeCollection(
    a.clients,
    b.clients,
    tombstones,
    historyLimit,
  );
  final projects = _mergeCollection(
    a.projects,
    b.projects,
    tombstones,
    historyLimit,
  );
  final tasks = _mergeCollection(a.tasks, b.tasks, tombstones, historyLimit);
  final entries = _mergeCollection(
    a.entries,
    b.entries,
    tombstones,
    historyLimit,
  );

  // Keyed by device, so two devices with live timers both survive rather than
  // one silently winning. DESIGN.md §3.6.
  final timers = _mergeCollection(
    a.runningTimers,
    b.runningTimers,
    tombstones,
    historyLimit,
  );

  final surviving = <String>{
    ...clients.keys,
    ...projects.keys,
    ...tasks.keys,
    ...entries.keys,
    ...timers.keys,
  };

  // A tombstone whose record came back (edited after the deletion) has done its
  // job and lost; drop it so the set does not grow without bound.
  tombstones.removeWhere((id, _) => surviving.contains(id));

  return CirrhyDocument(
    clients: clients,
    projects: projects,
    tasks: tasks,
    entries: entries,
    runningTimers: timers,
    tombstones: tombstones,
  );
}

/// Union by id; the later deletion wins.
Map<String, Tombstone> _mergeTombstones(
  Map<String, Tombstone> a,
  Map<String, Tombstone> b,
) {
  final out = <String, Tombstone>{};
  for (final id in {...a.keys, ...b.keys}) {
    final x = a[id], y = b[id];
    if (x == null) {
      out[id] = y!;
    } else if (y == null) {
      out[id] = x;
    } else {
      out[id] = x.deletedAt.isAfter(y.deletedAt) ? x : y;
    }
  }
  return out;
}

Map<String, T> _mergeCollection<T extends CirrhyRecord>(
  Map<String, T> mine,
  Map<String, T> theirs,
  Map<String, Tombstone> tombstones,
  int historyLimit,
) {
  final out = <String, T>{};
  for (final id in {...mine.keys, ...theirs.keys}) {
    final m = mine[id];
    final t = theirs[id];
    final T record;
    if (m != null && t != null) {
      record = mergeRecord(m, t, historyLimit: historyLimit);
    } else {
      record = (m ?? t)!;
    }

    // DESIGN.md §3.3: a deletion wins over a peer's edit only if it is newer.
    // The inverse matters just as much — editing after a delete revives the
    // record, which is how a mistaken deletion is undone on another device.
    final tomb = tombstones[id];
    if (tomb != null && tomb.deletedAt.isAfter(record.modified)) continue;

    out[id] = record;
  }
  return out;
}

/// Merges two versions of the same record.
T mergeRecord<T extends CirrhyRecord>(
  T mine,
  T theirs, {
  int historyLimit = defaultHistoryLimit,
}) {
  assert(mine.id == theirs.id, 'merge is by UUID; ids must match');

  final cmp = mine.modified.compareTo(theirs.modified);
  final (T winner, T loser) = switch (cmp) {
    > 0 => (mine, theirs),
    < 0 => (theirs, mine),
    _ => _breakTie(mine, theirs),
  };

  var result = winner;

  // DESIGN.md §3.5: location merges independently of the rest of the record, so
  // "moved on the phone, renamed on the laptop" keeps both the move and the
  // rename instead of the later edit reverting the earlier move.
  if (winner is RelocatableRecord && loser is RelocatableRecord) {
    if (loser.locationChanged.isAfter(winner.locationChanged)) {
      result = winner.withParent(loser.parentId, loser.locationChanged) as T;
    }
  }

  final history = _mergeHistory(winner, loser, historyLimit);
  return result.withHistory(history) as T;
}

/// Deterministic, symmetric tie-break for identical timestamps.
///
/// Two devices writing in the same millisecond is unlikely but not impossible,
/// and an arbitrary choice here would make the merge non-commutative: the
/// result would depend on which document was passed first. Ordering by the
/// canonical encoding of the fields removes that dependency.
(T, T) _breakTie<T extends CirrhyRecord>(T a, T b) {
  final ka = _canonical(a.toFields());
  final kb = _canonical(b.toFields());
  final c = ka.compareTo(kb);
  if (c == 0) return (a, b); // genuinely identical — either will do
  return c > 0 ? (a, b) : (b, a);
}

String _canonical(Map<String, Object?> fields) {
  final sorted = Map.fromEntries(
    fields.entries.toList()..sort((x, y) => x.key.compareTo(y.key)),
  );
  return jsonEncode(sorted);
}

List<RecordVersion> _mergeHistory(
  CirrhyRecord winner,
  CirrhyRecord loser,
  int limit,
) {
  final all = <RecordVersion>[...winner.history, ...loser.history];

  // The loser's own state is only worth keeping if it actually differed.
  if (_canonical(winner.toFields()) != _canonical(loser.toFields())) {
    all.add(loser.snapshot());
  }

  final seen = <String>{};
  final deduped = <RecordVersion>[];
  for (final v in all) {
    final key = '${v.modified.toIso8601String()}|${_canonical(v.fields)}';
    if (seen.add(key)) deduped.add(v);
  }

  deduped.sort(); // newest first
  return deduped.length <= limit ? deduped : deduped.sublist(0, limit);
}
