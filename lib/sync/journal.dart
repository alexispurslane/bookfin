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

  final String account;
  final String replica;
  final void Function(Map<String, dynamic>)? validateValue;
  final Map<String, Map<String, dynamic>> _actions = {};
  final Map<String, int> _coverage = {};
  final Map<String, List<Map<String, dynamic>>> _records = {};
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

  void persisted() {
    additions.clear();
    changedRecords.clear();
    changedCoverage.clear();
    acknowledged.clear();
  }

  static String identity(Map<String, dynamic> action) =>
      'action.${action['replica']}.${action['sequence']}';

  Map<String, dynamic> encode() => {
    'version': 1,
    'replica': replica,
    'actions': _actions.values.toList(),
    'pending': pending.toList(),
    'cursor': cursor,
  };

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

  void change(
    String record,
    Map<String, dynamic>? value, {
    bool resolve = false,
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
    };
    receive([action]);
    _pending.add(identity(action));
  }

  void receive(Iterable<Map<String, dynamic>> actions) {
    final candidates = Queue<String>();
    for (final original in actions) {
      final action = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
      _validate(action);
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
        if (previous == null ||
            previous['record'] != action['record'] ||
            (previous['sequence'] as int) >
                (context[previous['replica']] ?? 0)) {
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
  }

  void _validate(Map<String, dynamic> action) {
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
    final address = jsonDecode(record);
    if (address is! List ||
        address.length != 3 ||
        !const ['audio', 'reading'].contains(address[0]) ||
        !const ['bookmarks', 'history', 'resumes'].contains(address[1]) ||
        address[2] is! String ||
        (address[2] as String).isEmpty) {
      throw const FormatException('Invalid personal-record address.');
    }
  }

  void checkInvariants() {
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
