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
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/document_location_preference.dart';
import '../storage/document_directory.dart';
import '../storage/document_location.dart';

/// Where the session is in its life.
enum SessionStatus {
  /// No folder chosen yet, or [DocumentSession.open] not called. First run
  /// sits here until the picker has been answered.
  idle,

  /// [DocumentSession.open] is reading the document.
  loading,

  /// The document is loaded and saves are going to the chosen folder.
  ready,

  /// The folder cannot be reached — a stale bookmark, a revoked permission, a
  /// deleted directory (§4.4). The in-memory document is kept; the screen that
  /// sees this sends the user back to the picker, and re-picking relocates the
  /// document rather than abandoning it.
  unavailable,
}

/// The open document, and the only path through which screens touch it.
///
/// Owns one [DocumentRepository] pointed at the folder in
/// [DocumentLocationPreference], and funnels every mutation through a single
/// serialized commit, so the engine's read-merge-write (§3.2) never runs twice
/// interleaved. Screens read [document] and the lookups below, listen for
/// changes, and never see a store or a codec.
class DocumentSession extends ChangeNotifier {
  DocumentSession({
    required this._directory,
    required this._locationPreference,
    this._backup,
    DateTime Function()? clock,
    String? deviceId,
  }) : _clock = clock ?? DateTime.now,
       deviceId = deviceId ?? uuidV4() {
    // Relocation is a save, not a settings write (§4.6). The preference is
    // the one source of truth for where the document lives, so the session
    // follows it rather than being told twice.
    _locationPreference.addListener(_onLocationChanged);
  }

  /// Creates a session whose device id survives restarts.
  ///
  /// The running timer is keyed by device id (§3.6); a fresh id on every
  /// launch would orphan the previous launch's timer as a "foreign" one. The
  /// id is minted once and kept in platform preferences — device-scoped state
  /// stays out of the document (§3.7), and this is the most device-scoped
  /// state there is.
  static Future<DocumentSession> start({
    required DocumentDirectory directory,
    required DocumentLocationPreference locationPreference,
    DocumentBackup? backup,
    DateTime Function()? clock,
    String? deviceId,
  }) async {
    return DocumentSession(
      directory: directory,
      locationPreference: locationPreference,
      backup: backup,
      clock: clock,
      deviceId: deviceId ?? await _loadOrMintDeviceId(),
    );
  }

  static const _deviceIdKey = 'device.id';

  static Future<String> _loadOrMintDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_deviceIdKey);
    if (stored != null && stored.isNotEmpty) return stored;
    final minted = uuidV4();
    await prefs.setString(_deviceIdKey, minted);
    return minted;
  }

  final DocumentDirectory _directory;
  final DocumentLocationPreference _locationPreference;
  final DocumentBackup? _backup;
  final DateTime Function() _clock;

  /// This device's identity in the document — the key of its running timer.
  final String deviceId;

  DocumentRepository? _repository;
  CirrhyDocument _document = const CirrhyDocument.empty();
  SessionStatus _status = SessionStatus.idle;
  Object? _lastError;
  DateTime? _lastRefreshed;
  int _lastRefreshNewRecords = 0;
  Set<String> _lastRefreshNewEntryIds = const {};
  Set<String> _acknowledgedForeignTimers = const {};

  /// Every operation that touches the repository runs on this chain, one at a
  /// time, in order. Two rapid mutations therefore commit as two complete
  /// read-merge-write cycles instead of interleaving — the second one derives
  /// its change from the document the first one produced.
  Future<void> _queue = Future<void>.value();

  /// The document as this session knows it. Empty until [open] has loaded.
  CirrhyDocument get document => _document;

  SessionStatus get status => _status;

  /// The most recent failure, cleared by the next successful save or load.
  Object? get lastError => _lastError;

  /// When [refresh] last completed, in this session's clock (UTC).
  DateTime? get lastRefreshed => _lastRefreshed;

  /// How many records the last [refresh] brought in — the honest, cheap
  /// signal behind a "merged N changes" notice. Zero when nothing changed;
  /// never negative.
  int get lastRefreshNewRecords => _lastRefreshNewRecords;

  /// The entry ids the last [refresh] merged in from outside — the rows the
  /// timer list marks as "new from another device". Recomputed by every
  /// refresh, so the marks last exactly one refresh cycle and then simply
  /// stop being true, with no timers involved.
  Set<String> get lastRefreshNewEntryIds => _lastRefreshNewEntryIds;

  /// Completes once everything queued so far has run. Await after triggering
  /// an indirect operation — a relocation via the preference — to observe its
  /// result.
  Future<void> get idle => _queue;

  // ---- Reads -------------------------------------------------------------

  /// This device's running timer, if one is running.
  RunningTimer? get myTimer => _document.runningTimers[deviceId];

  /// Timers running on other devices. Non-empty means two devices tracked at
  /// once and the UI must surface reconciliation, never resolve it silently
  /// (§3.6).
  List<RunningTimer> get foreignTimers => _document.foreignTimers(deviceId);

  /// Whether the reconciliation prompt is owed to the user: a foreign timer
  /// exists that [acknowledgeForeignTimers] has not yet waved through.
  ///
  /// Acknowledgment is keyed on the timer's identity *and* its start — a
  /// restarted timer on the same device is a new fact and prompts again.
  bool get hasUnacknowledgedForeignTimers => foreignTimers.any(
    (timer) => !_acknowledgedForeignTimers.contains(_timerSignature(timer)),
  );

  /// "Keep both running": records that the user has seen exactly the foreign
  /// timers running now, so the prompt stays away for this set and returns
  /// the moment a different one appears.
  ///
  /// Held in memory only, deliberately. Which prompts this device has
  /// dismissed is device-scoped state (§3.7) — written into the document it
  /// would dismiss the same prompt on every other device, each of which has
  /// its own user-facing question to ask.
  void acknowledgeForeignTimers() {
    _acknowledgedForeignTimers = foreignTimers.map(_timerSignature).toSet();
    notifyListeners();
  }

  static String _timerSignature(RunningTimer timer) =>
      '${timer.deviceId}@${timer.startedAt.toIso8601String()}';

  Client? clientById(String? id) => id == null ? null : _document.clients[id];

  Project? projectById(String? id) =>
      id == null ? null : _document.projects[id];

  Task? taskById(String? id) => id == null ? null : _document.tasks[id];

  // ---- Lifecycle ---------------------------------------------------------

  /// Points the session at the chosen folder and loads the document.
  ///
  /// Does nothing while no folder is chosen; the location listener calls this
  /// again the moment first run picks one.
  Future<void> open() => _run(() async {
    final location = _locationPreference.location;
    if (location == null) return;

    _status = SessionStatus.loading;
    notifyListeners();
    try {
      final repository = _repositoryAt(location);
      _document = await repository.load();
      _repository = repository;
      _status = SessionStatus.ready;
      _lastError = null;
    } on DocumentLocationUnavailable catch (e) {
      _lastError = e;
      _status = SessionStatus.unavailable;
    } on DocumentFormatException catch (e) {
      // The file exists but cannot be read. Fail closed, exactly like the
      // engine's SaveBlockedException: keep no repository, so nothing this
      // session does can overwrite what might still be recoverable.
      _repository = null;
      _lastError = e;
      _status = SessionStatus.unavailable;
    }
    notifyListeners();
  });

  /// Re-reads the file and merges what changed underneath us.
  ///
  /// §4.4: nothing notifies us of external writes, so the app asks on every
  /// resume. A no-op when nothing is open yet.
  Future<void> refresh() => _run(() async {
    final repository = _repository;
    if (repository == null) return;

    try {
      final before = _document.recordCount;
      final entriesBefore = _document.entries.keys.toSet();
      _document = await repository.refresh(_document);
      _lastRefreshed = _now();
      final delta = _document.recordCount - before;
      _lastRefreshNewRecords = delta < 0 ? 0 : delta;
      _lastRefreshNewEntryIds = _document.entries.keys.toSet().difference(
        entriesBefore,
      );
      if (_status == SessionStatus.unavailable) _status = SessionStatus.ready;
      _lastError = null;
    } on DocumentLocationUnavailable catch (e) {
      _lastError = e;
      _status = SessionStatus.unavailable;
      _lastRefreshNewEntryIds = const {};
    } on DocumentFormatException catch (e) {
      // An external writer left an unreadable file. The in-memory document is
      // intact and saves stay blocked by the engine until the file is
      // readable again, so record the failure and carry on.
      _lastError = e;
      _lastRefreshNewEntryIds = const {};
    }
    notifyListeners();
  });

  // ---- Mutations ---------------------------------------------------------

  /// Starts this device's timer, stopping any already-running one first —
  /// into a logged entry, in the same commit, so no tracked interval is ever
  /// dropped. One timer per device (§3.6).
  Future<void> startTimer({
    String? projectId,
    String? taskId,
    String description = '',
  }) => _commit((doc) {
    final now = _now();
    return doc
        .stopTimer(deviceId, now)
        .put(
          RunningTimer(
            deviceId: deviceId,
            modified: now,
            startedAt: now,
            projectId: projectId,
            taskId: taskId,
            description: description,
          ),
        );
  });

  /// Edits this device's running timer's task/project and description in
  /// place. [RunningTimer.startedAt] is carried over untouched — the whole
  /// point is fixing metadata mid-run without losing the elapsed time — only
  /// [RunningTimer.modified] moves to now. A no-op when nothing is running on
  /// this device: there is nothing to edit into, which also covers the race
  /// where the timer stopped (locally or via another device's merge) while a
  /// caller was still composing the edit.
  Future<void> updateTimer({
    String? projectId,
    String? taskId,
    String description = '',
  }) => _commit((doc) {
    final current = doc.runningTimers[deviceId];
    if (current == null) return doc;
    return doc.put(
      RunningTimer(
        deviceId: deviceId,
        modified: _now(),
        startedAt: current.startedAt,
        projectId: projectId,
        taskId: taskId,
        description: description,
        importSource: current.importSource,
        externalId: current.externalId,
        history: current.history,
      ),
    );
  });

  /// Stops this device's timer, filing the interval as a [TimeEntry]. A no-op
  /// when nothing is running.
  Future<void> stopTimer() => _commit((doc) => doc.stopTimer(deviceId, _now()));

  /// "Stop it now" on the reconciliation prompt (§3.6): stops the timer that
  /// device [deviceId] left running, filing its interval as a [TimeEntry] —
  /// the tracked time is kept, only its open end is closed. The engine leaves
  /// a tombstone in the same commit, so the other device's next merge sees
  /// the stop rather than resurrecting the timer.
  Future<void> stopForeignTimer(String deviceId) =>
      _commit((doc) => doc.stopTimer(deviceId, _now()));

  /// One-tap restart: a new timer carrying a past entry's project, task and
  /// description. The primary interaction of the whole product.
  Future<void> restartFrom(TimeEntry entry) => startTimer(
    projectId: entry.projectId,
    taskId: entry.taskId,
    description: entry.description,
  );

  /// Adds or replaces [record].
  Future<void> put(CirrhyRecord record) => _commit((doc) => doc.put(record));

  /// Deletes the record with [id], leaving a tombstone so a peer's merge does
  /// not resurrect it (§3.3).
  Future<void> delete(String id) => _commit((doc) => doc.delete(id, _now()));

  // ---- Internals ---------------------------------------------------------

  DateTime _now() => _clock().toUtc();

  DocumentRepository _repositoryAt(DocumentLocation location) =>
      DocumentRepository(store: _directory.storeAt(location), backup: _backup);

  /// Appends [action] to the serial queue. The chain itself never carries an
  /// error forward — each action handles its own — but the caller still sees
  /// anything [action] throws.
  Future<void> _run(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// The single path every mutation takes.
  ///
  /// [change] is applied to the *current* document inside the queue, not
  /// outside it, so a mutation queued behind another builds on its
  /// predecessor's result instead of a stale snapshot. The saved (merged)
  /// document is always adopted — it may hold records this device has never
  /// seen.
  ///
  /// A failed save never discards the change: the mutated document stays in
  /// memory, the error is surfaced, and because every commit is a full
  /// read-merge-write, the next successful one persists everything.
  Future<void> _commit(CirrhyDocument Function(CirrhyDocument doc) change) =>
      _run(() async {
        final next = change(_document);
        final repository = _repository;
        if (repository == null) {
          // Nothing open (first run, or a load that failed closed). The work
          // is kept in memory; opening or relocating saves it.
          _document = next;
          notifyListeners();
          return;
        }
        try {
          _document = await repository.save(next);
          _status = SessionStatus.ready;
          _lastError = null;
        } on SaveBlockedException catch (e) {
          _document = next;
          _lastError = e;
        } on DocumentLocationUnavailable catch (e) {
          _document = next;
          _lastError = e;
          _status = SessionStatus.unavailable;
        }
        notifyListeners();
      });

  /// Relocation is a save (§4.6): point a repository at the new folder and
  /// save the in-memory document into it. Read-merge-write adopts whatever
  /// document the folder already holds — setting up the second device and
  /// moving the file are the same operation. The old file is never touched.
  Future<void> _relocate(DocumentLocation location) => _run(() async {
    DocumentRepository? repository;
    try {
      repository = _repositoryAt(location);
      _document = await repository.save(_document);
      _repository = repository;
      _status = SessionStatus.ready;
      _lastError = null;
    } on DocumentLocationUnavailable catch (e) {
      _lastError = e;
      _status = SessionStatus.unavailable;
    } on SaveBlockedException catch (e) {
      // The new folder holds a cirrhy.json nothing can read. The engine
      // refuses to overwrite it (fail closed), so keep working in memory and
      // keep retrying on later commits — the preference is the source of
      // truth for where the document lives, so the session points there even
      // while blocked.
      _repository = repository;
      _lastError = e;
    }
    notifyListeners();
  });

  void _onLocationChanged() {
    final location = _locationPreference.location;
    if (location == null) {
      // Cleared after a handle went stale (§4.4). Keep the document — it is
      // exactly the state the forced re-pick exists to save — and drop the
      // repository so nothing writes through a dead handle.
      _repository = null;
      if (_status != SessionStatus.idle) _status = SessionStatus.unavailable;
      notifyListeners();
      return;
    }
    if (_status == SessionStatus.idle) {
      // First run just answered the picker: open rather than relocate, since
      // there is nothing in memory worth saving over what the folder holds.
      unawaited(open());
    } else {
      unawaited(_relocate(location));
    }
  }

  @override
  void dispose() {
    _locationPreference.removeListener(_onLocationChanged);
    super.dispose();
  }
}
