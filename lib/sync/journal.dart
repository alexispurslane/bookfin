import 'dart:convert';
import 'dart:collection';

import 'package:flutter/foundation.dart';

class RecordJournal {
  RecordJournal(
    this.account,
    this.replica, [
    Map<String, dynamic>? saved,
    this.validateValue,
  ]) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(replica)) {
      throw const FormatException('Invalid installation identity.');
    }
    if (saved != null) {
      if (saved['version'] != 1 ||
          saved['replica'] != replica ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(replica) ||
          saved['actions'] is! List ||
          (saved['actions'] as List).any(
            (action) => action is! Map<String, dynamic>,
          ) ||
          saved['pending'] is! List ||
          (saved['pending'] as List).any((identity) => identity is! String) ||
          saved['cursor'] is! int ||
          (saved['cursor'] as int) < 0) {
        throw const FormatException('Unsupported personal-record journal.');
      }
      receive((saved['actions'] as List).cast<Map<String, dynamic>>());
      final pendingIdentities = (saved['pending'] as List).cast<String>();
      if (pendingIdentities.any(
        (identity) => !_actions.containsKey(identity),
      )) {
        throw const FormatException(
          'Pending personal records must reference retained actions.',
        );
      }
      _pending.addAll(pendingIdentities);
      cursor = saved['cursor'] as int;
    }
  }

  /// Restores the transaction's current versions and causal coverage. Only
  /// current and unapplied actions are resident; SQLite still owns every
  /// immutable payload. Pending identities need no payload until upload.
  RecordJournal.restore(
    this.account,
    this.replica, {
    required Map<String, dynamic> saved,
    required Map<String, List<String>> current,
    required Map<String, int> coverage,
    this.validateValue,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(replica) ||
        saved['cursor'] is! int ||
        (saved['cursor'] as int) < 0) {
      throw const FormatException(
        'Invalid committed journal identity or cursor.',
      );
    }
    _stored = true;
    cursor = saved['cursor'] as int;
    _coverage.addAll(coverage);
    _pending.addAll((saved['pending'] as List).cast<String>());
    for (final action
        in (saved['actions'] as List).cast<Map<String, dynamic>>()) {
      validateAction(account, action);
      validateValue?.call(action);
      _actions[identity(action)] = action;
    }
    final referenced = <String>{};
    for (final entry in current.entries) {
      final versions = <Map<String, dynamic>>[];
      for (final id in entry.value) {
        final action = _actions[id];
        if (action == null ||
            action['record'] != entry.key ||
            (action['sequence'] as int) > (_coverage[action['replica']] ?? 0) ||
            !referenced.add(id) ||
            (action['context'] as Map).entries.any(
              (entry) => (entry.value as int) > (_coverage[entry.key] ?? 0),
            )) {
          throw const FormatException(
            'Current versions must name applied actions of their record.',
          );
        }
        versions.add(action);
      }
      if (versions.isEmpty) {
        throw const FormatException('Current versions cannot be empty.');
      }
      _records[entry.key] = versions;
    }
    for (final action in _actions.values) {
      if ((action['sequence'] as int) <= (_coverage[action['replica']] ?? 0)) {
        continue;
      }
      var blocked = false;
      for (final dependency
          in (action['context'] as Map<String, dynamic>).entries) {
        if ((dependency.value as int) <= (_coverage[dependency.key] ?? 0)) {
          continue;
        }
        _waiting
            .putIfAbsent(dependency.key, () => SplayTreeMap())
            .putIfAbsent(dependency.value as int, () => {})
            .add(identity(action));
        blocked = true;
      }
      if (!blocked) {
        throw const FormatException(
          'Unapplied actions must wait for missing causal coverage.',
        );
      }
    }
  }

  bool _stored = false;

  /// Whether immutable payloads not needed by current state live on disk.
  bool get retainedOnDisk => _stored;

  /// Receives a page against disk-retained originals and preserved versions.
  /// Lookup payloads are temporary. Callers cannot install an independent
  /// inventory or bypass immutable duplicate and causal validation. [read]
  /// supplies guarded payloads decoded by the owner's storage worker.
  Future<Set<String>> receiveStored(
    List<Map<String, dynamic>> actions,
    Future<Map<String, Map<String, dynamic>>> Function(Set<String>) read,
  ) => _withOriginals(actions, read, () => receive(actions));

  /// Separates actions whose preserved conflict versions can be verified
  /// from malformed references and references that have not arrived yet.
  /// Neither excluded group supplies causal coverage. The store retains their
  /// wire originals and retries them after discovery supplies more originals.
  Future<
    ({
      List<Map<String, dynamic>> actions,
      Set<String> unreadable,
      Set<String> waiting,
    })
  >
  discoveryActions(
    List<Map<String, dynamic>> actions,
    Future<Map<String, Map<String, dynamic>>> Function(Set<String>) read,
  ) async {
    final needed = <String>{
      for (final action in actions)
        ...(action['preserve'] as List).cast<String>(),
    };
    if (needed.isEmpty) {
      return (actions: actions, unreadable: <String>{}, waiting: <String>{});
    }
    final originals = <String, Map<String, dynamic>>{
      for (final id in needed) id: ?_actions[id],
      for (final action in actions) identity(action): action,
    };
    if (_stored) {
      originals.addAll(await read(needed.difference(originals.keys.toSet())));
    }
    return compute(_classifyDiscovery, (
      actions: actions,
      originals: originals,
    ));
  }

  static ({
    List<Map<String, dynamic>> actions,
    Set<String> unreadable,
    Set<String> waiting,
  })
  _classifyDiscovery(
    ({
      List<Map<String, dynamic>> actions,
      Map<String, Map<String, dynamic>> originals,
    })
    input,
  ) {
    final accepted = <Map<String, dynamic>>[];
    final unreadable = <String>{};
    final waiting = <String>{};
    for (final action in input.actions) {
      final id = identity(action);
      for (final preserved in (action['preserve'] as List).cast<String>()) {
        final match = RegExp(r'^action\.([a-zA-Z0-9_-]{1,80})\.([1-9][0-9]*)$')
            .firstMatch(preserved);
        final sequence = match == null ? null : int.tryParse(match[2]!);
        if (sequence == null ||
            sequence > ((action['context'] as Map)[match![1]] as int? ?? 0)) {
          unreadable.add(id);
        } else if (input.originals[preserved] case final previous?) {
          if (!_validPreserved(action, previous)) unreadable.add(id);
        } else {
          waiting.add(id);
        }
      }
      if (!unreadable.contains(id) && !waiting.contains(id)) {
        accepted.add(action);
      }
    }
    waiting.removeAll(unreadable);
    return (actions: accepted, unreadable: unreadable, waiting: waiting);
  }

  static bool _validPreserved(
    Map<String, dynamic> action,
    Map<String, dynamic> previous,
  ) =>
      previous['record'] == action['record'] &&
      (previous['sequence'] as int) <=
          ((action['context'] as Map)[previous['replica']] as int? ?? 0);

  /// Changes a local record with the same retained-original checks as a
  /// received page: a local action can release held remote actions too.
  Future<void> changeStored(
    String record,
    Map<String, dynamic>? value, {
    required Future<Map<String, Map<String, dynamic>>> Function(Set<String>)
    read,
    bool resolve = false,
    String? device,
    DateTime? savedAt,
  }) => _withOriginals(
    const [],
    read,
    () => change(
      record,
      value,
      resolve: resolve,
      device: device,
      savedAt: savedAt,
    ),
  );

  Future<T> _withOriginals<T>(
    List<Map<String, dynamic>> actions,
    Future<Map<String, Map<String, dynamic>>> Function(Set<String>) read,
    T Function() apply,
  ) async {
    if (!_stored) return apply();
    final needed = <String>{};
    for (final action in actions) {
      validateAction(account, action);
      needed.add(identity(action));
      needed.addAll((action['preserve'] as List).cast<String>());
    }
    for (final action in _heldActions) {
      needed.addAll((action['preserve'] as List).cast<String>());
    }
    needed.removeAll(_actions.keys);
    final originals = await read(needed);
    for (final action in actions) {
      if ((action['sequence'] as int) <= (_coverage[action['replica']] ?? 0) &&
          !_actions.containsKey(identity(action)) &&
          !originals.containsKey(identity(action))) {
        throw const FormatException(
          'A covered action has no retained original.',
        );
      }
    }
    _actions.addAll(originals);
    try {
      return apply();
    } finally {
      _releasePayloads();
    }
  }

  Iterable<Map<String, dynamic>> get _heldActions => {
    for (final thresholds in _waiting.values)
      for (final ids in thresholds.values) ...ids,
  }.map((id) => _actions[id]!);

  void _releasePayloads() {
    final keep = <String>{
      for (final versions in _records.values) ...versions.map(identity),
      ..._heldActions.map(identity),
      ...additions.keys,
    };
    _actions.removeWhere((id, _) => !keep.contains(id));
    _ownLast.clear();
  }

  /// Pending payloads loaded only when transport asks. [read] returns the
  /// owner's guarded, detached payloads; validation runs in its worker.
  Future<List<Map<String, dynamic>>> storedUploads(
    Future<Map<String, Map<String, dynamic>>> Function(Set<String>) read,
  ) async {
    if (!_stored) return uploads;
    final actions = await read(_pending);
    if (_pending.any((id) => !actions.containsKey(id))) {
      throw const FormatException('A pending upload has no retained action.');
    }
    // Only references are ordered here, without encoding or decoding payloads.
    return [for (final id in _pending) actions[id]!];
  }

  /// The resident portion for recovery after the database file was kept
  /// aside. This is not a complete export; recovery joins the kept file.
  Map<String, dynamic> recoveryState() => {
    'version': 1,
    'replica': replica,
    'cursor': cursor,
    'actions': _actions.values.toList(),
    'pending': _pending.toList(),
  };

  final String account;
  final String replica;
  final void Function(Map<String, dynamic>)? validateValue;
  final Map<String, Map<String, dynamic>> _actions = {};
  final Map<String, int> _coverage = {};
  final Map<String, List<Map<String, dynamic>>> _records = {};

  /// The identity of the last action of this installation on each record
  /// that it changed, by address.
  final Map<String, String> _ownLast = {};
  final Set<String> _pending = {};
  Set<String> get pending => UnmodifiableSetView(_pending);
  int cursor = 0;
  final Map<String, SplayTreeMap<int, Set<String>>> _waiting = {};
  final Map<String, Map<String, dynamic>> additions = {};
  final Set<String> changedRecords = {};
  final Map<String, int> changedCoverage = {};
  final Set<String> acknowledged = {};

  Map<String, int> get coverage => Map.unmodifiable(_coverage);
  Map<String, List<String>> get current => {
    for (final entry in _records.entries) entry.key: versions(entry.key),
  };
  List<String> versions(String record) =>
      (_records[record] ?? []).map(identity).toList()..sort();

  void acknowledge(String identity) {
    if (_pending.remove(identity)) acknowledged.add(identity);
  }

  /// Marks the retained action [identity] as waiting for upload, as the
  /// kept copy that a recovered action came from marked it.
  void markPending(String identity) {
    if (!_actions.containsKey(identity)) {
      throw ArgumentError.value(identity, 'identity', 'is not retained');
    }
    _pending.add(identity);
    acknowledged.remove(identity);
  }

  void persisted({bool retainedOnDisk = false}) {
    additions.clear();
    changedRecords.clear();
    changedCoverage.clear();
    acknowledged.clear();
    if (retainedOnDisk) _stored = true;
    if (_stored) _releasePayloads();
  }

  /// The resident retained action [identity], or null. A disk-backed
  /// journal holds only current, held and uncommitted actions. Do not change it.
  Map<String, dynamic>? retained(String identity) => _actions[identity];

  /// The last retained action of this installation on [record], or null
  /// when it made none. Do not change it.
  Map<String, dynamic>? lastOwn(String record) => switch (_ownLast[record]) {
    null => null,
    final identity => _actions[identity],
  };

  static String identity(Map<String, dynamic> action) =>
      'action.${action['replica']}.${action['sequence']}';

  Map<String, dynamic> encode() {
    if (_stored) {
      throw StateError(
        'A complete journal export must read retained disk actions.',
      );
    }
    return {
      'version': 1,
      'replica': replica,
      'actions': _actions.values.toList(),
      'pending': pending.toList(),
      'cursor': cursor,
    };
  }

  List<Map<String, dynamic>> get uploads => [
    for (final id in pending) _actions[id]!,
  ];

  Map<String, List<Map<String, dynamic>>> get conflicts => {
    for (final entry in _records.entries)
      if (entry.value.length > 1) entry.key: List.unmodifiable(entry.value),
  };

  /// The current value of every record that has one, by address.
  Map<String, Map<String, dynamic>> get values => {
    for (final record in _records.keys) record: ?value(record),
  };

  /// The current versions of every record, by address, in the order in
  /// which the records first appeared. [currentValue] reads a record's value
  /// from its versions. Do not change the lists.
  Map<String, List<Map<String, dynamic>>> get versionsByRecord =>
      UnmodifiableMapView(_records);

  /// A copy of the current value of [record], or null when the record is
  /// absent or deleted, or is a resume with conflicting versions. Other
  /// conflicting records show their version with the lowest identity.
  Map<String, dynamic>? value(String record) {
    final versions = _records[record];
    return versions == null ? null : currentValue(record, versions);
  }

  /// A copy of the value of [record] whose current versions are
  /// [versions], as [value] defines it. It reads no journal, so a hop can
  /// derive values from [versionsByRecord].
  static Map<String, dynamic>? currentValue(
    String record,
    List<Map<String, dynamic>> versions,
  ) {
    if (versions.any((action) => action['value'] == null) ||
        versions.length > 1 && _isResume(record)) {
      return null;
    }
    final first = versions.reduce(
      (first, second) =>
          identity(first).compareTo(identity(second)) <= 0 ? first : second,
    );
    return Map<String, dynamic>.from(first['value'] as Map);
  }

  static bool _isResume(String record) =>
      (jsonDecode(record) as List)[1] == 'resumes';

  /// Adds an action of this installation that sets [record] to [value], or
  /// deletes it when [value] is null, and marks it for upload. With
  /// [resolve], the action replaces every competing version. Otherwise it
  /// keeps the versions of other installations that compete with this one.
  ///
  /// The action names the [device] that made the change and the time
  /// [savedAt], when the caller knows them, so that a choice between saved
  /// versions can say where each one came from. Actions from before these
  /// fields lack them, and every reader accepts an action with or without
  /// them.
  void change(
    String record,
    Map<String, dynamic>? value, {
    bool resolve = false,
    String? device,
    DateTime? savedAt,
  }) {
    final versions = _records[record] ?? [];
    final action = <String, dynamic>{
      'version': 1,
      'account': account,
      'replica': replica,
      'sequence': (_coverage[replica] ?? 0) + 1,
      'context': Map<String, int>.from(_coverage),
      'record': record,
      'value': value,
      'preserve': [
        if (!resolve && versions.length > 1)
          for (final previous in versions)
            if (previous['replica'] != replica) identity(previous),
      ],
      'device': ?device,
      'savedAt': ?savedAt?.toUtc().toIso8601String(),
    };
    receive([action]);
    _pending.add(identity(action));
  }

  /// Adds [actions] that the journal lacks and applies each one whose
  /// causal context it covers. Returns the addresses of the records whose
  /// current versions changed.
  ///
  /// Throws a [FormatException] when an action is invalid, or when it has
  /// the identity of a retained action but different content.
  Set<String> receive(Iterable<Map<String, dynamic>> actions) {
    final applied = <String>{};
    final candidates = Queue<String>();
    for (final original in actions) {
      final action = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
      validateAction(account, action);
      validateValue?.call(action);
      final id = identity(action);
      final previous = _actions[id];
      if (previous != null &&
          !const DeepCollectionEquality().equals(previous, action)) {
        throw const FormatException('An immutable sync action changed.');
      }
      if (previous == null) {
        _actions[id] = action;
        additions[id] = action;
        candidates.add(id);
        if (!_stored && action['replica'] == replica) _noteOwn(action);
      }
    }
    while (candidates.isNotEmpty) {
      final action = _actions[candidates.removeFirst()]!;
      final author = action['replica'] as String;
      final sequence = action['sequence'] as int;
      final context = Map<String, int>.from(action['context'] as Map);
      if (sequence <= (_coverage[author] ?? 0)) continue;
      var blocked = false;
      for (final dependency in context.entries) {
        if (dependency.value <= (_coverage[dependency.key] ?? 0)) continue;
        _waiting
            .putIfAbsent(dependency.key, () => SplayTreeMap())
            .putIfAbsent(dependency.value, () => {})
            .add(identity(action));
        blocked = true;
      }
      if (blocked) {
        continue;
      }
      assert(sequence == (_coverage[author] ?? 0) + 1);
      final versions = _records.putIfAbsent(
        action['record'] as String,
        () => [],
      );
      final preserved = (action['preserve'] as List).cast<String>();
      for (final id in preserved) {
        final previous = _actions[id];
        if (previous == null || !_validPreserved(action, previous)) {
          throw const FormatException(
            'A preserved conflict must be an observed version of the same record.',
          );
        }
      }
      versions.removeWhere(
        (old) =>
            (old['sequence'] as int) <= (context[old['replica']] ?? 0) &&
            !preserved.contains(identity(old)),
      );
      versions.add(action);
      _coverage[author] = sequence;
      applied.add(action['record'] as String);
      changedRecords.add(action['record'] as String);
      changedCoverage[author] = sequence;
      assert(identical(_actions[identity(action)], action));
      final waiting = _waiting[author];
      while (waiting != null &&
          waiting.isNotEmpty &&
          waiting.firstKey()! <= sequence) {
        candidates.addAll(waiting.remove(waiting.firstKey())!);
      }
    }
    return applied;
  }

  /// Makes [action] of this installation the last on its record, unless a
  /// later one is.
  void _noteOwn(Map<String, dynamic> action) {
    final record = action['record'] as String;
    final last = lastOwn(record);
    if (last == null ||
        (last['sequence'] as int) < (action['sequence'] as int)) {
      _ownLast[record] = identity(action);
    }
  }

  /// Checks the immutable action envelope before its domain value is decoded.
  /// This guard can run beside a retained-payload read in a worker.
  static void validateAction(String account, Map<String, dynamic> action) {
    final author = action['replica'];
    final sequence = action['sequence'];
    final context = action['context'];
    final record = action['record'];
    final preserved = action['preserve'];
    if (action['version'] != 1 ||
        action['account'] != account ||
        author is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(author) ||
        sequence is! int ||
        sequence < 1 ||
        context is! Map<String, dynamic> ||
        context.entries.any(
          (entry) =>
              !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(entry.key) ||
              entry.value is! int ||
              (entry.value as int) < 0,
        ) ||
        (context[author] ?? 0) != sequence - 1 ||
        record is! String ||
        preserved is! List ||
        preserved.any((id) => id is! String) ||
        (action['value'] != null && action['value'] is! Map<String, dynamic>)) {
      throw const FormatException('Invalid personal-record sync action.');
    }
    // NOTE: The journal accepts any domain and collection, so that a build
    // keeps and syncs the records of a newer build. Its owner decides which
    // records it reads.
    final address = jsonDecode(record);
    if (address is! List ||
        address.length != 3 ||
        address.any((part) => part is! String || part.isEmpty)) {
      throw const FormatException('Invalid personal-record address.');
    }
  }

  Map<String, Map<int, List<String>>> get _dependencies => {
    for (final entry in _waiting.entries)
      if (entry.value.isNotEmpty)
        entry.key: {
          for (final threshold in entry.value.entries)
            threshold.key: threshold.value.toList()..sort(),
        },
  };

  /// Checks resident payloads and held dependencies against an independent
  /// full replay. Only the owner's explicit invariant verification calls it.
  void checkRetained(RecordJournal replay) {
    if (_actions.entries.any(
          (entry) => !const DeepCollectionEquality().equals(
            entry.value,
            replay.retained(entry.key),
          ),
        ) ||
        !const DeepCollectionEquality().equals(
          _dependencies,
          replay._dependencies,
        )) {
      throw StateError(
        'Resident actions and held dependencies must agree with retained originals.',
      );
    }
  }

  void checkInvariants() {
    if (_stored) {
      if (cursor < 0 ||
          _records.values.any(
            (versions) =>
                versions.isEmpty ||
                versions.any(
                  (action) =>
                      !identical(_actions[identity(action)], action) ||
                      (action['sequence'] as int) >
                          (_coverage[action['replica']] ?? 0),
                ),
          )) {
        throw StateError('Resident versions must be retained applied actions.');
      }
      return;
    }
    final ownLast = <String, Map<String, dynamic>>{};
    for (final action in _actions.values) {
      if (action['replica'] != replica) continue;
      final last = ownLast[action['record'] as String];
      if (last == null ||
          (last['sequence'] as int) < (action['sequence'] as int)) {
        ownLast[action['record'] as String] = action;
      }
    }
    if (ownLast.length != _ownLast.length ||
        ownLast.entries.any(
          (entry) => _ownLast[entry.key] != identity(entry.value),
        )) {
      throw StateError(
        'The last own action of each record must be the newest one.',
      );
    }
    final held = <String>{};
    for (final entry in _waiting.entries) {
      for (final threshold in entry.value.entries) {
        if (threshold.key <= (_coverage[entry.key] ?? 0)) {
          throw StateError(
            'Waiting actions must need unapplied causal coverage.',
          );
        }
        held.addAll(threshold.value);
      }
    }
    if (cursor < 0 ||
        pending.any((id) => !_actions.containsKey(id)) ||
        held.any((id) => !_actions.containsKey(id)) ||
        _coverage.entries.any(
          (entry) =>
              Iterable<int>.generate(entry.value, (index) => index + 1).any(
                (sequence) =>
                    !_actions.containsKey('action.${entry.key}.$sequence'),
              ),
        ) ||
        _actions.entries.any(
          (entry) =>
              (entry.value['sequence'] as int) >
                  (_coverage[entry.value['replica']] ?? 0) &&
              !held.contains(entry.key),
        ) ||
        _records.values.any(
          (versions) =>
              versions.isEmpty ||
              versions.any(
                (action) =>
                    !identical(_actions[identity(action)], action) ||
                    (action['sequence'] as int) >
                        (_coverage[action['replica']] ?? 0),
              ),
        )) {
      throw StateError(
        'Journal actions, pending uploads, and causal coverage must agree.',
      );
    }
  }
}

class DeepCollectionEquality {
  const DeepCollectionEquality();
  bool equals(Object? first, Object? second) {
    if (first is Map && second is Map) {
      return first.length == second.length &&
          first.keys.every(
            (key) => second.containsKey(key) && equals(first[key], second[key]),
          );
    }
    if (first is List && second is List) {
      return listEquals(first, second) ||
          first.length == second.length &&
              Iterable<int>.generate(first.length)
                  .every((index) => equals(first[index], second[index]));
    }
    return first == second;
  }
}
