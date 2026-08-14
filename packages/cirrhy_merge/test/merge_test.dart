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

import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:test/test.dart';

/// DESIGN.md §9: the highest-value tests are the adversarial merge cases —
/// concurrent edits to one entry, a delete racing an edit, and two devices with
/// simultaneously running timers.
void main() {
  group('union over UUIDs', () {
    test('records only one side has are carried through', () {
      final a = const CirrhyDocument.empty().put(
        entry('e1', mod: 10, start: 9),
      );
      final b = const CirrhyDocument.empty().put(
        entry('e2', mod: 11, start: 9),
      );

      final merged = mergeDocuments(a, b);

      expect(merged.entries.keys, unorderedEquals(['e1', 'e2']));
    });

    test('identical records on both sides do not duplicate', () {
      final e = entry('e1', mod: 10, start: 9);
      final merged = mergeDocuments(
        const CirrhyDocument.empty().put(e),
        const CirrhyDocument.empty().put(e),
      );

      expect(merged.entries, hasLength(1));
      expect(merged.entries['e1']!.history, isEmpty);
    });
  });

  group('concurrent edits to one entry', () {
    test('newer last-modified wins', () {
      final mine = entry('e1', mod: 10, start: 9, desc: 'laptop');
      final theirs = entry('e1', mod: 20, start: 9, desc: 'phone');

      final merged = mergeRecord(mine, theirs);

      expect(merged.description, 'phone');
    });

    test('the loser is demoted to history, not destroyed', () {
      final mine = entry('e1', mod: 10, start: 9, desc: 'laptop');
      final theirs = entry('e1', mod: 20, start: 9, desc: 'phone');

      final merged = mergeRecord(mine, theirs);

      expect(merged.history, hasLength(1));
      expect(merged.history.single.fields['description'], 'laptop');
      expect(merged.history.single.modified, t(10));
    });

    test('history is capped, newest kept', () {
      var e = entry('e1', mod: 0, start: 9, desc: 'v0');
      for (var i = 1; i <= 30; i++) {
        e = mergeRecord(
          e,
          entry('e1', mod: i, start: 9, desc: 'v$i'),
          historyLimit: 5,
        );
      }

      expect(e.description, 'v30');
      expect(e.history, hasLength(5));
      expect(e.history.map((h) => h.fields['description']), [
        'v29',
        'v28',
        'v27',
        'v26',
        'v25',
      ]);
    });
  });

  group('start and stop merge as a unit', () {
    // DESIGN.md §3.1: never field-merge a start from one device with a stop
    // from another — the result is a duration nobody recorded.
    test('the winning entry keeps its own start/stop pair', () {
      final mine = entry('e1', mod: 10, start: 9, stop: 11);
      final theirs = entry('e1', mod: 20, start: 14, stop: 15);

      final merged = mergeRecord(mine, theirs);

      expect(merged.start, t(14));
      expect(merged.stop, t(15));
      expect(merged.duration, const Duration(minutes: 1));
    });
  });

  group('a delete racing an edit', () {
    test('a newer deletion beats an older edit', () {
      final deleted = const CirrhyDocument.empty()
          .put(entry('e1', mod: 10, start: 9))
          .delete('e1', t(30));
      final edited = const CirrhyDocument.empty().put(
        entry('e1', mod: 20, start: 9),
      );

      final merged = mergeDocuments(deleted, edited);

      expect(merged.entries, isEmpty);
      expect(merged.tombstones.containsKey('e1'), isTrue);
    });

    test('a newer edit revives the record and retires the tombstone', () {
      // How a mistaken deletion gets undone from another device.
      final deleted = const CirrhyDocument.empty()
          .put(entry('e1', mod: 10, start: 9))
          .delete('e1', t(20));
      final edited = const CirrhyDocument.empty().put(
        entry('e1', mod: 30, start: 9, desc: 'still wanted'),
      );

      final merged = mergeDocuments(deleted, edited);

      expect(merged.entries['e1']?.description, 'still wanted');
      expect(merged.tombstones, isEmpty);
    });

    test('without the peer holding it, a deleted record stays deleted', () {
      // The bug tombstones exist to prevent: a plain union resurrects whatever
      // the other device deleted, and it is invisible until days later.
      final deleted = const CirrhyDocument.empty()
          .put(entry('e1', mod: 10, start: 9))
          .delete('e1', t(30));
      final peerStillHasIt = const CirrhyDocument.empty().put(
        entry('e1', mod: 10, start: 9),
      );

      final merged = mergeDocuments(deleted, peerStillHasIt);

      expect(merged.entries, isEmpty, reason: 'e1 must not come back');
    });
  });

  group('two devices with simultaneously running timers', () {
    // DESIGN.md §3.6: last-write-wins here silently discards a tracked
    // interval — precisely the data the app exists to protect.
    test('both timers survive the merge', () {
      final phone = const CirrhyDocument.empty().put(
        timer('phone', mod: 10, startedAt: 9),
      );
      final laptop = const CirrhyDocument.empty().put(
        timer('laptop', mod: 12, startedAt: 11),
      );

      final merged = mergeDocuments(phone, laptop);

      expect(merged.runningTimers.keys, unorderedEquals(['phone', 'laptop']));
    });

    test('the app can see the foreign timer to prompt for reconciliation', () {
      final merged = mergeDocuments(
        const CirrhyDocument.empty().put(timer('phone', mod: 10, startedAt: 9)),
        const CirrhyDocument.empty().put(
          timer('laptop', mod: 12, startedAt: 11),
        ),
      );

      final foreign = merged.foreignTimers('phone');

      expect(foreign, hasLength(1));
      expect(foreign.single.deviceId, 'laptop');
    });

    test('the same device restarting its timer is still last-write-wins', () {
      final merged = mergeRecord(
        timer('phone', mod: 10, startedAt: 9),
        timer('phone', mod: 20, startedAt: 19),
      );

      expect(merged.startedAt, t(19));
    });

    test('stopping files an entry and tombstones the timer', () {
      final running = const CirrhyDocument.empty().put(
        timer('phone', mod: 10, startedAt: 9, desc: 'writing'),
      );

      final stopped = running.stopTimer('phone', t(30));

      expect(stopped.runningTimers, isEmpty);
      expect(stopped.entries.values.single.description, 'writing');
      expect(
        stopped.entries.values.single.duration,
        const Duration(minutes: 21),
      );

      // A peer that still holds the running timer must not restart it.
      final merged = mergeDocuments(stopped, running);
      expect(
        merged.runningTimers,
        isEmpty,
        reason: 'a stopped timer must not be resurrected by a peer',
      );
      expect(merged.entries, hasLength(1));
    });
  });

  group('moved vs edited', () {
    // DESIGN.md §3.5: relocating and editing merge independently.
    test('a move on one device survives a later edit on the other', () {
      final moved = entry('e1', mod: 10, start: 9, project: 'p2', loc: 40);
      final edited = entry(
        'e1',
        mod: 50,
        start: 9,
        desc: 'renamed',
        project: 'p1',
        loc: 5,
      );

      final merged = mergeRecord(moved, edited);

      expect(merged.description, 'renamed', reason: 'newer edit wins');
      expect(merged.projectId, 'p2', reason: 'newer move wins independently');
    });

    test('an older move does not override a newer one', () {
      final merged = mergeRecord(
        entry('e1', mod: 10, start: 9, project: 'p2', loc: 20),
        entry('e1', mod: 50, start: 9, project: 'p3', loc: 40),
      );

      expect(merged.projectId, 'p3');
    });
  });

  group('algebraic properties', () {
    // These are what make it safe to run the merge on every save without
    // knowing which side is "ours".
    final a = const CirrhyDocument.empty()
        .put(entry('e1', mod: 10, start: 9, desc: 'a'))
        .put(entry('e2', mod: 12, start: 9))
        .put(timer('phone', mod: 10, startedAt: 9))
        .delete('e3', t(15));
    final b = const CirrhyDocument.empty()
        .put(entry('e1', mod: 20, start: 9, desc: 'b'))
        .put(entry('e3', mod: 11, start: 9))
        .put(timer('laptop', mod: 12, startedAt: 11));

    test('commutative', () {
      expect(canonical(mergeDocuments(a, b)), canonical(mergeDocuments(b, a)));
    });

    test('idempotent', () {
      final once = mergeDocuments(a, b);
      final twice = mergeDocuments(once, once);
      expect(canonical(twice), canonical(once));
    });

    test('merging a document with the empty document is a no-op', () {
      expect(
        canonical(mergeDocuments(a, const CirrhyDocument.empty())),
        canonical(a),
      );
    });

    test('commutative even when timestamps tie exactly', () {
      final x = const CirrhyDocument.empty().put(
        entry('e1', mod: 10, start: 9, desc: 'alpha'),
      );
      final y = const CirrhyDocument.empty().put(
        entry('e1', mod: 10, start: 9, desc: 'beta'),
      );

      expect(canonical(mergeDocuments(x, y)), canonical(mergeDocuments(y, x)));
    });
  });
}

// ---- helpers ----

DateTime t(int minute) =>
    DateTime.utc(2026, 8, 13, 10).add(Duration(minutes: minute));

TimeEntry entry(
  String id, {
  required int mod,
  required int start,
  int? stop,
  String desc = '',
  String? project,
  int? loc,
}) => TimeEntry(
  id: id,
  modified: t(mod),
  start: t(start),
  stop: stop == null ? null : t(stop),
  projectId: project,
  locationChanged: t(loc ?? mod),
  description: desc,
);

RunningTimer timer(
  String deviceId, {
  required int mod,
  required int startedAt,
  String desc = '',
}) => RunningTimer(
  deviceId: deviceId,
  modified: t(mod),
  startedAt: t(startedAt),
  description: desc,
);

/// Encodes a document to its canonical bytes, so two documents can be compared
/// for deep equality. Doubles as a check that the codec's ordering is stable.
String canonical(CirrhyDocument doc) =>
    utf8.decode(const JsonDocumentCodec().encode(doc));
