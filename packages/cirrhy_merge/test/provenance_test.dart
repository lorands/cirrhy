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
import 'dart:io';

import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:test/test.dart';

/// DESIGN.md §10: `importSource` and `externalId` make an import batch
/// addressable after the fact. They are traceability, never merge keys — the
/// tests here pin both halves of that: the fields survive every path a record
/// travels (codec, merge, history), and the engine attaches no semantics to
/// them beyond carrying them.
void main() {
  final t0 = DateTime.utc(2026, 8, 14, 9);
  const source = 'kimai - truenas';

  TimeEntry importedEntry({
    String id = 'e1',
    DateTime? modified,
    String desc = 'imported work',
  }) {
    final m = modified ?? t0;
    return TimeEntry(
      id: id,
      modified: m,
      start: m.subtract(const Duration(hours: 2)),
      stop: m.subtract(const Duration(hours: 1)),
      projectId: 'p1',
      locationChanged: m,
      description: desc,
      importSource: source,
      externalId: 'timesheet:1842',
    );
  }

  group('provenance fields (§10)', () {
    test('round-trip through the codec on every record type', () {
      final doc = const CirrhyDocument.empty()
          .put(
            Client(
              id: 'c1',
              modified: t0,
              name: 'Acme',
              importSource: source,
              externalId: 'customer:3',
            ),
          )
          .put(
            Project(
              id: 'p1',
              modified: t0,
              name: 'Website',
              clientId: 'c1',
              locationChanged: t0,
              importSource: source,
              externalId: 'project:7',
            ),
          )
          .put(
            Task(
              id: 't1',
              modified: t0,
              name: 'Landing',
              projectId: 'p1',
              locationChanged: t0,
              importSource: source,
              externalId: 'activity:9',
            ),
          )
          .put(importedEntry())
          .put(
            RunningTimer(
              deviceId: 'device-x',
              modified: t0,
              startedAt: t0,
              importSource: source,
              externalId: 'timer:1',
            ),
          );

      const codec = JsonDocumentCodec();
      final decoded = codec.decode(codec.encode(doc));

      expect(decoded.clients['c1']!.importSource, source);
      expect(decoded.clients['c1']!.externalId, 'customer:3');
      expect(decoded.projects['p1']!.importSource, source);
      expect(decoded.projects['p1']!.externalId, 'project:7');
      expect(decoded.tasks['t1']!.importSource, source);
      expect(decoded.tasks['t1']!.externalId, 'activity:9');
      expect(decoded.entries['e1']!.importSource, source);
      expect(decoded.entries['e1']!.externalId, 'timesheet:1842');
      expect(decoded.runningTimers['device-x']!.importSource, source);
      expect(decoded.runningTimers['device-x']!.externalId, 'timer:1');
    });

    test('hand-made records serialize without the keys at all', () {
      final doc = const CirrhyDocument.empty().put(
        TimeEntry(
          id: 'e1',
          modified: t0,
          start: t0.subtract(const Duration(hours: 1)),
          stop: t0,
          projectId: null,
          locationChanged: t0,
          description: 'logged by hand',
        ),
      );

      final json = utf8.decode(const JsonDocumentCodec().encode(doc));

      expect(json, isNot(contains('importSource')));
      expect(json, isNot(contains('externalId')));
    });

    test('a v1 document without the fields still decodes, as null', () {
      final v1 = utf8.encode(
        jsonEncode({
          'format': 'cirrhy',
          'formatVersion': 1,
          'entries': [
            {
              'id': 'e1',
              'modified': t0.toIso8601String(),
              'locationChanged': t0.toIso8601String(),
              'start': t0.subtract(const Duration(hours: 1)).toIso8601String(),
              'stop': t0.toIso8601String(),
              'projectId': null,
              'taskId': null,
              'description': 'old file',
              'billable': false,
            },
          ],
        }),
      );

      final decoded = const JsonDocumentCodec().decode(v1);

      expect(decoded.entries['e1']!.importSource, isNull);
      expect(decoded.entries['e1']!.externalId, isNull);
    });

    test('encode stamps formatVersion 2 and decode refuses newer', () {
      final bytes = const JsonDocumentCodec().encode(
        const CirrhyDocument.empty(),
      );
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      expect(map['formatVersion'], CirrhyDocument.formatVersion);

      final newer = utf8.encode(
        jsonEncode({
          'format': 'cirrhy',
          'formatVersion': CirrhyDocument.formatVersion + 1,
        }),
      );
      expect(
        () => const JsonDocumentCodec().decode(newer),
        throwsA(isA<DocumentFormatException>()),
      );
    });

    test('an edit losing to a merge demotes provenance into the history '
        'snapshot, and the winner keeps its own', () {
      final imported = importedEntry(modified: t0);
      final edited = TimeEntry(
        id: 'e1',
        modified: t0.add(const Duration(minutes: 5)),
        start: imported.start,
        stop: imported.stop,
        projectId: 'p1',
        locationChanged: imported.locationChanged,
        description: 'edited after import',
        importSource: imported.importSource,
        externalId: imported.externalId,
      );

      final merged = mergeRecord(imported, edited);

      expect(merged.description, 'edited after import');
      expect(merged.importSource, source);
      expect(merged.externalId, 'timesheet:1842');
      expect(merged.history.single.fields['importSource'], source);
      expect(merged.history.single.fields['externalId'], 'timesheet:1842');
    });

    test('the §10 rollback protocol: tombstoning a batch keeps it dead '
        'against a peer that still holds it', () {
      // Both sides start with the imported batch plus one hand-made entry.
      final imported = [
        importedEntry(id: 'i1'),
        importedEntry(id: 'i2', desc: 'more imported work'),
      ];
      final byHand = TimeEntry(
        id: 'h1',
        modified: t0,
        start: t0.subtract(const Duration(minutes: 30)),
        stop: t0,
        projectId: null,
        locationChanged: t0,
        description: 'logged by hand',
      );
      var mine = const CirrhyDocument.empty().put(byHand);
      var theirs = const CirrhyDocument.empty().put(byHand);
      for (final e in imported) {
        mine = mine.put(e);
        theirs = theirs.put(e);
      }

      // Rollback on this side, exactly as doc/llms.md prescribes: delete
      // every record whose importSource matches, leaving tombstones.
      final rollbackAt = t0.add(const Duration(hours: 1));
      for (final e in mine.entries.values.toList()) {
        if (e.importSource == source) mine = mine.delete(e.id, rollbackAt);
      }

      // The peer never heard about the rollback; merging must not resurrect.
      final merged = mergeDocuments(mine, theirs);

      expect(merged.entries.keys, ['h1']);
      expect(merged.tombstones.keys, unorderedEquals(['i1', 'i2']));
    });
  });

  group('the schema stays in step with the code', () {
    final schema =
        jsonDecode(File('doc/cirrhy-document.schema.json').readAsStringSync())
            as Map<String, Object?>;
    final defs = schema[r'$defs'] as Map<String, Object?>;

    // What the encoder emits for a fully-populated record of each type —
    // provenance set and history non-empty, so every optional key appears.
    final history = [
      RecordVersion(
        modified: t0.subtract(const Duration(days: 1)),
        fields: const {'name': 'old'},
      ),
    ];
    final full = const CirrhyDocument.empty()
        .put(
          Client(
            id: 'c1',
            modified: t0,
            name: 'Acme',
            importSource: source,
            externalId: 'customer:3',
            history: history,
          ),
        )
        .put(
          Project(
            id: 'p1',
            modified: t0,
            name: 'Website',
            clientId: 'c1',
            locationChanged: t0,
            color: '#336699',
            importSource: source,
            externalId: 'project:7',
            history: history,
          ),
        )
        .put(
          Task(
            id: 't1',
            modified: t0,
            name: 'Landing',
            projectId: 'p1',
            locationChanged: t0,
            importSource: source,
            externalId: 'activity:9',
            history: history,
          ),
        )
        .put(importedEntry().withHistory(history))
        .put(
          RunningTimer(
            deviceId: 'device-x',
            modified: t0,
            startedAt: t0,
            projectId: 'p1',
            taskId: 't1',
            importSource: source,
            externalId: 'timer:1',
            history: history,
          ),
        )
        .delete('gone', t0);

    final encoded =
        jsonDecode(utf8.decode(const JsonDocumentCodec().encode(full)))
            as Map<String, Object?>;

    Set<String> emittedKeys(String collection) {
      final list = encoded[collection] as List;
      return (list.single as Map<String, Object?>).keys.toSet();
    }

    (Set<String>, Set<String>) schemaKeys(String def) {
      final d = defs[def] as Map<String, Object?>;
      final properties = (d['properties'] as Map<String, Object?>).keys.toSet();
      final required = (d['required'] as List).cast<String>().toSet();
      return (properties, required);
    }

    const collections = {
      'clients': 'client',
      'projects': 'project',
      'tasks': 'task',
      'entries': 'timeEntry',
      'runningTimers': 'runningTimer',
      'tombstones': 'tombstone',
    };

    for (final MapEntry(key: collection, value: def) in collections.entries) {
      test('$collection: schema properties match what the codec emits', () {
        final emitted = emittedKeys(collection);
        final (properties, required) = schemaKeys(def);

        expect(
          properties,
          emitted,
          reason:
              'doc/cirrhy-document.schema.json "$def" must list exactly the '
              'keys the codec writes — update the schema with the code',
        );
        // Everything is required except what the encoder emits only when
        // present; a tombstone has no such keys.
        final optional = def == 'tombstone'
            ? const <String>{}
            : const {'importSource', 'externalId', 'history'};
        expect(required, emitted.difference(optional), reason: '"$def"');
      });
    }

    test('the envelope and formatVersion match too', () {
      final properties = (schema['properties'] as Map<String, Object?>).keys
          .toSet();
      expect(properties, encoded.keys.toSet());

      final versionDef =
          (schema['properties'] as Map<String, Object?>)['formatVersion']
              as Map<String, Object?>;
      expect(versionDef['const'], CirrhyDocument.formatVersion);
    });
  });
}
