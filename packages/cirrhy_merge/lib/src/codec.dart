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

import 'package:crypto/crypto.dart';

import 'document.dart';
import 'records.dart';

/// Thrown when a file cannot be read as a Cirrhy document.
///
/// Never swallowed into an empty document: silently starting fresh on an
/// unreadable file is how a user's entire history gets overwritten with
/// nothing on the next save.
final class DocumentFormatException implements Exception {
  const DocumentFormatException(this.message);
  final String message;
  @override
  String toString() => 'DocumentFormatException: $message';
}

/// Encodes and decodes the document.
///
/// DESIGN.md §5 decided JSON (2026-08-14). The interface stays as the escape
/// hatch: a future format change would swap the implementation without
/// reaching into the merge engine.
abstract interface class DocumentCodec {
  List<int> encode(CirrhyDocument doc);
  CirrhyDocument decode(List<int> bytes);
}

/// JSON, pretty-printed with sorted keys.
///
/// Chosen as the default because an OSS user may need to inspect or repair
/// their own data, and because it diffs. The stable key order also means an
/// unchanged document re-encodes to identical bytes, which the content-hash
/// change detection in [DocumentRepository] depends on.
final class JsonDocumentCodec implements DocumentCodec {
  const JsonDocumentCodec({this.indent = '  '});

  final String indent;

  @override
  List<int> encode(CirrhyDocument doc) {
    final map = <String, Object?>{
      'format': 'cirrhy',
      'formatVersion': CirrhyDocument.formatVersion,
      'clients': _sorted(doc.clients.values.map(_record)),
      'projects': _sorted(doc.projects.values.map(_record)),
      'tasks': _sorted(doc.tasks.values.map(_record)),
      'entries': _sorted(doc.entries.values.map(_record)),
      'runningTimers': _sorted(doc.runningTimers.values.map(_record)),
      'tombstones': _sorted(doc.tombstones.values.map((t) => t.toFields())),
    };
    return utf8.encode(JsonEncoder.withIndent(indent).convert(map));
  }

  @override
  CirrhyDocument decode(List<int> bytes) {
    if (bytes.isEmpty) return const CirrhyDocument.empty();

    final Object? parsed;
    try {
      parsed = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw DocumentFormatException('not valid JSON: ${e.message}');
    }
    if (parsed is! Map<String, Object?>) {
      throw const DocumentFormatException('top level is not an object');
    }
    if (parsed['format'] != 'cirrhy') {
      throw const DocumentFormatException('not a Cirrhy document');
    }

    final version = parsed['formatVersion'];
    if (version is! int || version > CirrhyDocument.formatVersion) {
      throw DocumentFormatException(
        'formatVersion $version is newer than this build understands '
        '(${CirrhyDocument.formatVersion}) — refusing to read it, because '
        'writing it back would drop whatever this build cannot represent',
      );
    }

    return CirrhyDocument(
      clients: _index(parsed['clients'], _client),
      projects: _index(parsed['projects'], _project),
      tasks: _index(parsed['tasks'], _task),
      entries: _index(parsed['entries'], _entry),
      runningTimers: _index(parsed['runningTimers'], _timer, key: 'deviceId'),
      tombstones: _indexTombstones(parsed['tombstones']),
    );
  }

  // ---- encoding helpers ----

  static List<Map<String, Object?>> _sorted(
    Iterable<Map<String, Object?>> items,
  ) =>
      items.toList()
        ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

  static Map<String, Object?> _record(CirrhyRecord r) => {
    'id': r.id,
    'modified': r.modified.toUtc().toIso8601String(),
    if (r is RelocatableRecord)
      'locationChanged': r.locationChanged.toUtc().toIso8601String(),
    ...r.toFields(),
    if (r.history.isNotEmpty)
      'history': [
        for (final v in r.history)
          {'modified': v.modified.toUtc().toIso8601String(), ...v.fields},
      ],
  };

  // ---- decoding helpers ----

  static Map<String, T> _index<T>(
    Object? raw,
    T Function(Map<String, Object?>) build, {
    String key = 'id',
  }) {
    if (raw == null) return const {};
    if (raw is! List) throw const DocumentFormatException('expected a list');
    final out = <String, T>{};
    for (final item in raw) {
      if (item is! Map<String, Object?>) {
        throw const DocumentFormatException('expected a list of objects');
      }
      out[_str(item, key)] = build(item);
    }
    return out;
  }

  static Map<String, Tombstone> _indexTombstones(Object? raw) {
    if (raw == null) return const {};
    if (raw is! List) throw const DocumentFormatException('expected a list');
    final out = <String, Tombstone>{};
    for (final item in raw) {
      if (item is! Map<String, Object?>) {
        throw const DocumentFormatException('expected a list of objects');
      }
      final id = _str(item, 'id');
      out[id] = Tombstone(id: id, deletedAt: _time(item, 'deletedAt'));
    }
    return out;
  }

  static Client _client(Map<String, Object?> m) => Client(
    id: _str(m, 'id'),
    modified: _time(m, 'modified'),
    name: _str(m, 'name'),
    archived: m['archived'] == true,
    importSource: m['importSource'] as String?,
    externalId: m['externalId'] as String?,
    history: _history(m),
  );

  static Project _project(Map<String, Object?> m) => Project(
    id: _str(m, 'id'),
    modified: _time(m, 'modified'),
    name: _str(m, 'name'),
    clientId: m['clientId'] as String?,
    locationChanged: _time(m, 'locationChanged'),
    color: m['color'] as String?,
    billable: m['billable'] == true,
    archived: m['archived'] == true,
    importSource: m['importSource'] as String?,
    externalId: m['externalId'] as String?,
    history: _history(m),
  );

  static Task _task(Map<String, Object?> m) => Task(
    id: _str(m, 'id'),
    modified: _time(m, 'modified'),
    name: _str(m, 'name'),
    projectId: m['projectId'] as String?,
    locationChanged: _time(m, 'locationChanged'),
    archived: m['archived'] == true,
    importSource: m['importSource'] as String?,
    externalId: m['externalId'] as String?,
    history: _history(m),
  );

  static TimeEntry _entry(Map<String, Object?> m) => TimeEntry(
    id: _str(m, 'id'),
    modified: _time(m, 'modified'),
    start: _time(m, 'start'),
    stop: m['stop'] == null ? null : _time(m, 'stop'),
    projectId: m['projectId'] as String?,
    locationChanged: _time(m, 'locationChanged'),
    taskId: m['taskId'] as String?,
    description: (m['description'] as String?) ?? '',
    billable: m['billable'] == true,
    importSource: m['importSource'] as String?,
    externalId: m['externalId'] as String?,
    history: _history(m),
  );

  static RunningTimer _timer(Map<String, Object?> m) => RunningTimer(
    deviceId: _str(m, 'deviceId'),
    modified: _time(m, 'modified'),
    startedAt: _time(m, 'startedAt'),
    projectId: m['projectId'] as String?,
    taskId: m['taskId'] as String?,
    description: (m['description'] as String?) ?? '',
    importSource: m['importSource'] as String?,
    externalId: m['externalId'] as String?,
    history: _history(m),
  );

  static List<RecordVersion> _history(Map<String, Object?> m) {
    final raw = m['history'];
    if (raw == null) return const [];
    if (raw is! List) {
      throw const DocumentFormatException('history must be a list');
    }
    return [
      for (final v in raw)
        if (v is Map<String, Object?>)
          RecordVersion(
            modified: _time(v, 'modified'),
            fields: {...v}..remove('modified'),
          ),
    ];
  }

  static String _str(Map<String, Object?> m, String key) {
    final v = m[key];
    if (v is! String) {
      throw DocumentFormatException('missing or non-string "$key"');
    }
    return v;
  }

  static DateTime _time(Map<String, Object?> m, String key) {
    final v = m[key];
    if (v is! String) {
      throw DocumentFormatException('missing or non-string timestamp "$key"');
    }
    final parsed = DateTime.tryParse(v);
    if (parsed == null) {
      throw DocumentFormatException('"$key" is not an ISO-8601 instant: $v');
    }
    return parsed.toUtc();
  }
}

/// SHA-256 of the bytes as they sit on disk.
///
/// DESIGN.md §3.2: detect change by content hash, **not mtime** — sync clients
/// rewrite mtimes for their own reasons and Keepass2Android hashes for exactly
/// this reason.
String contentHash(List<int> bytes) => sha256.convert(bytes).toString();
