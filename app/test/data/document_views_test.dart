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

import 'package:cirrhy/data/document_views.dart';
import 'package:cirrhy_merge/cirrhy_merge.dart';
import 'package:flutter_test/flutter_test.dart';

CirrhyDocument _doc({
  Map<String, Client> clients = const {},
  Map<String, Project> projects = const {},
  Map<String, Task> tasks = const {},
  Map<String, TimeEntry> entries = const {},
}) => CirrhyDocument(
  clients: clients,
  projects: projects,
  tasks: tasks,
  entries: entries,
);

TimeEntry _entry(
  String id, {
  required DateTime start,
  DateTime? stop,
  String? projectId,
  String? taskId,
  bool billable = false,
}) => TimeEntry(
  id: id,
  modified: start,
  start: start,
  stop: stop,
  projectId: projectId,
  taskId: taskId,
  billable: billable,
  locationChanged: start,
);

void main() {
  final now = DateTime.utc(2026, 8, 13, 9);

  group('isEffectivelyArchived', () {
    test('a client is archived exactly by its own flag', () {
      final doc = _doc(
        clients: {
          'c1': Client(id: 'c1', modified: now, name: 'Acme', archived: true),
          'c2': Client(id: 'c2', modified: now, name: 'Globex'),
        },
      );
      expect(isEffectivelyArchived(doc, doc.clients['c1']!), isTrue);
      expect(isEffectivelyArchived(doc, doc.clients['c2']!), isFalse);
    });

    test('a project is archived when its client is, even if its own flag is '
        'false', () {
      final doc = _doc(
        clients: {
          'c1': Client(id: 'c1', modified: now, name: 'Acme', archived: true),
        },
        projects: {
          'p1': Project(
            id: 'p1',
            modified: now,
            name: 'Website',
            clientId: 'c1',
            locationChanged: now,
          ),
        },
      );
      expect(isEffectivelyArchived(doc, doc.projects['p1']!), isTrue);
    });

    test('a project with no client and its own flag false is not archived', () {
      final doc = _doc(
        projects: {
          'p1': Project(
            id: 'p1',
            modified: now,
            name: 'Freelance',
            clientId: null,
            locationChanged: now,
          ),
        },
      );
      expect(isEffectivelyArchived(doc, doc.projects['p1']!), isFalse);
    });

    test('a task cascades through its project up to its client', () {
      final doc = _doc(
        clients: {
          'c1': Client(id: 'c1', modified: now, name: 'Acme', archived: true),
        },
        projects: {
          'p1': Project(
            id: 'p1',
            modified: now,
            name: 'Website',
            clientId: 'c1',
            locationChanged: now,
          ),
        },
        tasks: {
          't1': Task(
            id: 't1',
            modified: now,
            name: 'Landing page',
            projectId: 'p1',
            locationChanged: now,
          ),
        },
      );
      // The task's own flag is false throughout — only the client is
      // archived — yet it must read as effectively archived.
      expect(doc.tasks['t1']!.archived, isFalse);
      expect(isEffectivelyArchived(doc, doc.tasks['t1']!), isTrue);
    });

    test('a task under a live project and live client is not archived', () {
      final doc = _doc(
        clients: {'c1': Client(id: 'c1', modified: now, name: 'Acme')},
        projects: {
          'p1': Project(
            id: 'p1',
            modified: now,
            name: 'Website',
            clientId: 'c1',
            locationChanged: now,
          ),
        },
        tasks: {
          't1': Task(
            id: 't1',
            modified: now,
            name: 'Landing page',
            projectId: 'p1',
            locationChanged: now,
          ),
        },
      );
      expect(isEffectivelyArchived(doc, doc.tasks['t1']!), isFalse);
    });

    test('a task whose project reference is dangling is not archived', () {
      final doc = _doc(
        tasks: {
          't1': Task(
            id: 't1',
            modified: now,
            name: 'Orphan',
            projectId: 'missing',
            locationChanged: now,
          ),
        },
      );
      expect(isEffectivelyArchived(doc, doc.tasks['t1']!), isFalse);
    });
  });

  group('totalFor', () {
    test('sums only closed entries for the given project', () {
      final doc = _doc(
        entries: {
          'e1': _entry(
            'e1',
            start: DateTime.utc(2026, 8, 1, 9),
            stop: DateTime.utc(2026, 8, 1, 10),
            projectId: 'p1',
          ),
          'e2': _entry(
            'e2',
            start: DateTime.utc(2026, 8, 1, 9),
            stop: DateTime.utc(2026, 8, 1, 11),
            projectId: 'p2',
          ),
          // Still open — must not contribute.
          'e3': TimeEntry(
            id: 'e3',
            modified: now,
            start: DateTime.utc(2026, 8, 1, 9),
            stop: null,
            projectId: 'p1',
            locationChanged: now,
          ),
        },
      );
      expect(totalFor(doc, projectId: 'p1'), const Duration(hours: 1));
    });

    test('sums by client, resolving through the entry\'s project', () {
      final doc = _doc(
        clients: {'c1': Client(id: 'c1', modified: now, name: 'Acme')},
        projects: {
          'p1': Project(
            id: 'p1',
            modified: now,
            name: 'Website',
            clientId: 'c1',
            locationChanged: now,
          ),
          'p2': Project(
            id: 'p2',
            modified: now,
            name: 'Other client',
            clientId: 'other',
            locationChanged: now,
          ),
        },
        entries: {
          'e1': _entry(
            'e1',
            start: DateTime.utc(2026, 8, 1, 9),
            stop: DateTime.utc(2026, 8, 1, 10),
            projectId: 'p1',
          ),
          'e2': _entry(
            'e2',
            start: DateTime.utc(2026, 8, 1, 9),
            stop: DateTime.utc(2026, 8, 1, 12),
            projectId: 'p2',
          ),
        },
      );
      expect(totalFor(doc, clientId: 'c1'), const Duration(hours: 1));
    });

    test('a half-open [from, to) window excludes the instant at "to"', () {
      final doc = _doc(
        entries: {
          'inside': _entry(
            'inside',
            start: DateTime(2026, 8, 31, 23),
            stop: DateTime(2026, 8, 31, 23, 30),
          ),
          'atBoundary': _entry(
            'atBoundary',
            start: DateTime(2026, 9, 1),
            stop: DateTime(2026, 9, 1, 1),
          ),
        },
      );
      final total = totalFor(
        doc,
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 9, 1),
      );
      expect(total, const Duration(minutes: 30));
    });
  });

  group('currentMonthWindow', () {
    test('bounds the local calendar month, not the UTC one', () {
      // 23:30 local on the last day of August is already September 1st in
      // UTC+1 or later — the window must still be August's, computed on the
      // local calendar rather than the UTC instant.
      final localNow = DateTime(2026, 8, 31, 23, 30);
      final (from, to) = currentMonthWindow(localNow);
      expect(from, DateTime(2026, 8));
      expect(to, DateTime(2026, 9));
    });

    test('December rolls into next January', () {
      final (from, to) = currentMonthWindow(DateTime(2026, 12, 15));
      expect(from, DateTime(2026, 12));
      expect(to, DateTime(2027, 1));
    });

    test('an entry just before midnight on the last day counts, one just '
        'after the boundary does not', () {
      final doc = _doc(
        entries: {
          'lastMinute': _entry(
            'lastMinute',
            start: DateTime(2026, 8, 31, 23, 59),
            stop: DateTime(2026, 9, 1, 0, 30),
          ),
          'nextMonth': _entry(
            'nextMonth',
            start: DateTime(2026, 9, 1, 0, 1),
            stop: DateTime(2026, 9, 1, 1),
          ),
        },
      );
      final (from, to) = currentMonthWindow(DateTime(2026, 8, 31, 12));
      final total = totalFor(doc, from: from, to: to);
      // Only the entry whose *local start* falls in August counts, even
      // though it runs past midnight into September.
      expect(total, const Duration(minutes: 31));
    });
  });

  group('entriesInRange', () {
    // One project per client, so the client axis can only be satisfied by
    // resolving an entry through its project.
    final doc = _doc(
      clients: {
        'acme': Client(id: 'acme', modified: now, name: 'Acme'),
        'cirrhy': Client(id: 'cirrhy', modified: now, name: 'Cirrhy'),
      },
      projects: {
        'web': Project(
          id: 'web',
          modified: now,
          name: 'Website',
          clientId: 'acme',
          locationChanged: now,
        ),
        'core': Project(
          id: 'core',
          modified: now,
          name: 'Core',
          clientId: 'cirrhy',
          locationChanged: now,
        ),
      },
      entries: {
        'web1': _entry(
          'web1',
          start: DateTime(2026, 8, 10, 9),
          stop: DateTime(2026, 8, 10, 12),
          projectId: 'web',
          taskId: 'design',
          billable: true,
        ),
        'core1': _entry(
          'core1',
          start: DateTime(2026, 8, 11, 9),
          stop: DateTime(2026, 8, 11, 11),
          projectId: 'core',
        ),
        'loose': _entry(
          'loose',
          start: DateTime(2026, 8, 12, 9),
          stop: DateTime(2026, 8, 12, 10),
        ),
        'open': _entry('open', start: DateTime(2026, 8, 12, 14)),
        'lastWeek': _entry(
          'lastWeek',
          start: DateTime(2026, 8, 5, 9),
          stop: DateTime(2026, 8, 5, 10),
          projectId: 'web',
        ),
      },
    );

    final from = DateTime(2026, 8, 10);
    final to = DateTime(2026, 8, 17);

    List<String> ids(List<TimeEntry> entries) =>
        entries.map((e) => e.id).toList();

    test('keeps the window\'s closed entries and drops the open one', () {
      expect(
        ids(entriesInRange(doc, from: from, to: to)),
        // Newest first, and the still-running entry contributes nothing.
        ['loose', 'core1', 'web1'],
      );
    });

    test('an empty axis filters nothing rather than everything', () {
      expect(
        entriesInRange(doc, from: from, to: to, clientIds: const {}).length,
        3,
      );
    });

    test('the client axis resolves through the entry\'s project', () {
      expect(
        ids(entriesInRange(doc, from: from, to: to, clientIds: {'acme'})),
        ['web1'],
      );
    });

    test('an entry with no project can never match a client filter', () {
      expect(
        ids(
          entriesInRange(
            doc,
            from: from,
            to: to,
            clientIds: {'acme', 'cirrhy'},
          ),
        ),
        ['core1', 'web1'],
      );
    });

    test('the axes AND with each other', () {
      // Acme owns Website, so Acme + Core can match nothing at all —
      // selecting a client must not widen the project axis.
      expect(
        entriesInRange(
          doc,
          from: from,
          to: to,
          clientIds: {'acme'},
          projectIds: {'core'},
        ),
        isEmpty,
      );
      expect(
        ids(
          entriesInRange(
            doc,
            from: from,
            to: to,
            clientIds: {'acme'},
            projectIds: {'web'},
          ),
        ),
        ['web1'],
      );
    });

    test('the task axis narrows within a matching project', () {
      expect(
        ids(entriesInRange(doc, from: from, to: to, taskIds: {'design'})),
        ['web1'],
      );
      expect(
        entriesInRange(doc, from: from, to: to, taskIds: {'other'}),
        isEmpty,
      );
    });

    test('billableOnly drops everything not marked billable', () {
      expect(ids(entriesInRange(doc, from: from, to: to, billableOnly: true)), [
        'web1',
      ]);
    });

    test('an unbounded call sees every closed entry in the document', () {
      expect(entriesInRange(doc).length, 4);
    });
  });

  group('aggregations', () {
    test('sumOf adds closed durations and ignores an open entry', () {
      final entries = [
        _entry(
          'a',
          start: DateTime(2026, 8, 10, 9),
          stop: DateTime(2026, 8, 10, 10, 30),
        ),
        _entry('open', start: DateTime(2026, 8, 10, 12)),
      ];
      expect(sumOf(entries), const Duration(hours: 1, minutes: 30));
      expect(sumOf(const <TimeEntry>[]), Duration.zero);
    });

    test('dailyTotals counts an entry on the local day it started, even when '
        'it runs past midnight', () {
      final totals = dailyTotals([
        _entry(
          'evening',
          start: DateTime(2026, 8, 13, 23, 30),
          stop: DateTime(2026, 8, 14, 0, 30),
        ),
        _entry(
          'morning',
          start: DateTime(2026, 8, 13, 8),
          stop: DateTime(2026, 8, 13, 9),
        ),
      ]);
      // Both on the 13th; nothing at all lands on the 14th, even though an
      // hour of the first entry was spent there.
      expect(totals, {DateTime(2026, 8, 13): const Duration(hours: 2)});
      expect(totals[DateTime(2026, 8, 14)], isNull);
    });

    test('dailyTotals leaves days with nothing on them absent', () {
      final totals = dailyTotals([
        _entry(
          'a',
          start: DateTime(2026, 8, 10, 9),
          stop: DateTime(2026, 8, 10, 10),
        ),
        _entry(
          'b',
          start: DateTime(2026, 8, 12, 9),
          stop: DateTime(2026, 8, 12, 10),
        ),
      ]);
      expect(totals.keys, {DateTime(2026, 8, 10), DateTime(2026, 8, 12)});
    });

    test('projectTotals buckets project-less time under the null key', () {
      final totals = projectTotals([
        _entry(
          'a',
          start: DateTime(2026, 8, 10, 9),
          stop: DateTime(2026, 8, 10, 12),
          projectId: 'web',
        ),
        _entry(
          'b',
          start: DateTime(2026, 8, 10, 13),
          stop: DateTime(2026, 8, 10, 14),
          projectId: 'web',
        ),
        _entry(
          'c',
          start: DateTime(2026, 8, 11, 9),
          stop: DateTime(2026, 8, 11, 10),
        ),
      ]);
      expect(totals, {
        'web': const Duration(hours: 4),
        null: const Duration(hours: 1),
      });
    });
  });

  group('localDay', () {
    test('is the local midnight of the instant\'s day', () {
      expect(localDay(DateTime(2026, 8, 13, 23, 59)), DateTime(2026, 8, 13));
      expect(localDay(DateTime(2026, 8, 13)), DateTime(2026, 8, 13));
    });
  });
}
