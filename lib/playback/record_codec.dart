import 'dart:convert';

import '../catalog/model.dart';
import 'records.dart';

/// The collections of each domain that this build reads.
const _collections = {
  'audio': {'bookmarks', 'history', 'resumes'},
  'reading': {'bookmarks', 'history', 'resumes'},
};

/// Whether this build knows the domain and the collection of [address].
bool knownRecordAddress(List<dynamic> address) =>
    _collections[address[0]]?.contains(address[1]) ?? false;

/// Whether this build reads the record at [record] with [value], or its
/// deletion when [value] is null: this build knows its address, and a
/// history entry names a kind of move that this build knows. A kind that is
/// not a string is no newer kind, so its record counts as read, and its
/// decoding fails as damage.
bool readableRecord(String record, Map<String, dynamic>? value) {
  final address = jsonDecode(record) as List;
  if (!knownRecordAddress(address)) return false;
  final kind = value?['kind'];
  return address[1] != 'history' ||
      kind is! String ||
      HistoryAction.values.any((known) => known.name == kind);
}

/// Throws a [FormatException] when the value of [action] is damaged: this
/// build reads its record ([readableRecord]), but the value does not decode.
void validateRecordAction(Map<String, dynamic> action) {
  final value = action['value'] as Map<String, dynamic>?;
  if (value == null || !readableRecord(action['record'] as String, value)) {
    return;
  }
  final address = jsonDecode(action['record'] as String) as List;
  final reading = address[0] == 'reading';
  try {
    switch (address[1]) {
      case 'bookmarks':
        if (value['id'] != address[2]) throw const FormatException();
        if (reading) {
          Bookmark.fromJson(value, decodeTextPosition);
        } else {
          Bookmark.fromJson(value, decodePosition);
        }
      case 'history':
        if (value['id'] != address[2]) throw const FormatException();
        if (reading) {
          HistoryEvent.fromJson(value, decodeTextPosition);
        } else {
          HistoryEvent.fromJson(value, decodePosition);
        }
      case 'resumes':
        if (reading) {
          decodeTextPosition(value);
        } else {
          decodePosition(value);
        }
        final projected = reading
            ? {
                'reading': {
                  'resumes': [value],
                },
              }
            : {
                'resumes': {
                  value['edition'] as String: [
                    <String, dynamic>{...value}..remove('edition'),
                  ],
                },
              };
        if (!flattenRecords(
          projected,
          reading: reading,
        ).containsKey(action['record'])) {
          throw const FormatException();
        }
    }
  } on FormatException {
    throw const FormatException(
      'A personal record is invalid. Existing records were kept.',
    );
  } on TypeError {
    // Record decoders also use checked casts for persisted field types.
    throw const FormatException(
      'A personal record is invalid. Existing records were kept.',
    );
  }
}

/// The listening or reading snapshot of an account with [metadata] and the
/// record [values] of the journal: the domain's settings plus
/// the current value of each of its records that this build reads
/// ([readableRecord]), as a fresh copy. It changes the listening resumes of
/// [values].
Map<String, dynamic> recordSnapshot(
  Map<String, dynamic> metadata,
  Map<String, Map<String, dynamic>> values, {
  required bool reading,
}) {
  final domain = reading ? 'reading' : 'audio';
  final snapshot = <String, dynamic>{
    ...reading
        ? metadata['reading'] as Map<String, dynamic>
        : (Map.of(metadata)..remove('reading')),
    'bookmarks': <dynamic>[],
    'history': <dynamic>[],
    'resumes': reading ? <dynamic>[] : <String, dynamic>{},
  };
  for (final entry in values.entries) {
    final address = jsonDecode(entry.key) as List;
    if (address[0] != domain || !readableRecord(entry.key, entry.value)) {
      continue;
    }
    final collection = address[1] as String;
    final value = entry.value;
    if (!reading && collection == 'resumes') {
      final edition = value.remove('edition') as String;
      ((snapshot['resumes'] as Map).putIfAbsent(
        edition,
        () => <dynamic>[],
      ) as List).add(value);
    } else {
      (snapshot[collection] as List).add(value);
    }
  }
  return jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
}

/// The records in the selected domain of [combined], keyed by their stable
/// journal addresses. Accepts both current and legacy listening resumes.
/// Returned values are shallow copies; whole-snapshot callers copy nested
/// values at their ownership boundary.
Map<String, Map<String, dynamic>> flattenRecords(
  Map<String, dynamic> combined, {
  required bool reading,
}) {
  final domain = reading ? 'reading' : 'audio';
  final snapshot = reading
      ? combined['reading'] as Map<String, dynamic>?
      : combined;
  if (snapshot == null) return {};
  for (final collection in ['bookmarks', 'history', if (reading) 'resumes']) {
    final values = snapshot[collection];
    if (values != null &&
        (values is! List ||
            values.any((value) => value is! Map<String, dynamic>))) {
      throw const FormatException('Invalid personal-record collection.');
    }
  }
  final result = <String, Map<String, dynamic>>{};
  if (!reading &&
      snapshot['resumes'] != null &&
      snapshot['resumes'] is! Map<String, dynamic>) {
    throw const FormatException('Listening resumes must be an object.');
  }
  for (final collection in ['bookmarks', 'history']) {
    for (final value in (snapshot[collection] as List? ?? []).cast<Map>()) {
      result[jsonEncode([domain, collection, value['id']])] =
          Map<String, dynamic>.from(value);
    }
  }
  if (reading) {
    for (final value in (snapshot['resumes'] as List? ?? []).cast<Map>()) {
      final address = jsonEncode([
        value['edition'],
        value['source'],
        value['revision'],
      ]);
      result[jsonEncode([domain, 'resumes', address])] =
          Map<String, dynamic>.from(value);
    }
  } else {
    for (final entry in (snapshot['resumes'] as Map? ?? {}).entries) {
      final values = entry.value is List ? entry.value as List : [entry.value];
      for (final raw in values) {
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('A listening resume must be an object.');
        }
        final value = Map<String, dynamic>.from(raw as Map);
        final address = jsonEncode([
          entry.key,
          if (value['sources'] != null)
            value['sources']
          else ...[
            value['source'],
            value['revision'],
          ],
        ]);
        result[jsonEncode([domain, 'resumes', address])] = {
          ...value,
          'edition': entry.key,
        };
      }
    }
  }
  return result;
}

/// Each record of [combined], a snapshot in the format before the journal,
/// that decodes on its own, by address, as [flattenRecords] reads it.
Iterable<MapEntry<String, Map<String, dynamic>>> recoverableRecords(
  Map<String, dynamic> combined,
) sync* {
  for (final reading in [false, true]) {
    final snapshot = reading ? combined['reading'] : combined;
    if (snapshot is! Map<String, dynamic>) continue;
    final pieces = <Map<String, dynamic>>[
      for (final collection in ['bookmarks', 'history', if (reading) 'resumes'])
        if (snapshot[collection] case final List values)
          for (final value in values)
            {
              collection: [value],
            },
      if (!reading && snapshot['resumes'] is Map<String, dynamic>)
        for (final MapEntry(key: edition, :value)
            in (snapshot['resumes'] as Map<String, dynamic>).entries)
          for (final place in value is List ? value : [value])
            {
              'resumes': {
                edition: [place],
              },
            },
    ];
    for (final piece in pieces) {
      try {
        yield* flattenRecords(
          reading ? {'reading': piece} : piece,
          reading: reading,
        ).entries;
      } on FormatException {
        continue;
      }
    }
  }
}

/// The resume address for the exact text source or set of audio sources in
/// [edition]. Replaced sources have a different address and keep old places.
String resumeRecordAddress(Edition edition) {
  final reading = edition.kind == EditionKind.text;
  return jsonEncode([
    if (reading) 'reading' else 'audio',
    'resumes',
    if (reading)
      jsonEncode([
        edition.id,
        edition.files.single.key,
        edition.files.single.revision,
      ])
    else
      jsonEncode([edition.id, editionSources(edition)]),
  ]);
}
