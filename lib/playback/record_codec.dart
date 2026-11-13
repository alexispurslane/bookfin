import 'dart:convert';

import '../catalog/model.dart';
import '../sync/journal.dart';
import '../sync/record_address.dart';
import 'records.dart';

/// The collections of each domain that this build reads.
const _collections = {
  'audio': {'bookmarks', 'history', 'resumes'},
  'reading': {'bookmarks', 'history', 'resumes'},
};

String _recordAddress(String domain, String collection, Object? id) {
  if (id is! String) {
    throw const FormatException('Invalid personal-record address.');
  }
  return RecordAddress(domain, collection, id).encoded;
}

/// Whether this build knows the domain and the collection of [address].
bool knownRecordAddress(RecordAddress address) =>
    _collections[address.domain]?.contains(address.collection) ?? false;

/// Whether this build reads the record at [address] with [value], or its
/// deletion when [value] is null: this build knows its address, and a
/// history entry names a kind of move that this build knows. A kind that is
/// not a string is no newer kind, so its record counts as read, and its
/// decoding fails as damage.
bool readableRecord(RecordAddress address, Map<String, dynamic>? value) {
  if (!knownRecordAddress(address)) return false;
  final kind = value?['kind'];
  return address.collection != 'history' ||
      kind is! String ||
      HistoryAction.values.any((known) => known.name == kind);
}

/// Throws a [FormatException] when the value of [action] is damaged: this
/// build reads its record ([readableRecord]), but the value does not decode.
void validateRecordAction(Map<String, dynamic> action) {
  final address = RecordAddress.parse(action['record'] as String);
  final value = action['value'] as Map<String, dynamic>?;
  if (readableRecord(address, value)) _decodeRecordValue(address, value);
}

/// A supported personal-record value, decoded by the same path that validates
/// journal actions. These views contain no mutable wire maps.
sealed class RecordValue {
  const RecordValue();

  /// The saved place, bookmark place, or destination of a history move.
  Place get position;

  /// The saved book title, or null when the record does not supply one.
  String? get bookTitle;
}

/// A listening or reading resume, without its persistence-only fields.
final class ResumeValue extends RecordValue {
  const ResumeValue(this.position, this.bookTitle);
  @override
  final Place position;
  @override
  final String? bookTitle;
}

/// A bookmark decoded with the position decoder of its domain.
final class BookmarkValue extends RecordValue {
  const BookmarkValue(this.bookmark);
  final Bookmark<Place> bookmark;
  @override
  Place get position => bookmark.position;
  @override
  String? get bookTitle => bookmark.bookTitle;
}

/// A history move decoded with the position decoder of its domain.
final class HistoryValue extends RecordValue {
  const HistoryValue(this.event);
  final HistoryEvent<Place> event;
  @override
  Place get position => event.after;
  @override
  String get bookTitle => event.bookTitle;
}

/// A detached, read-only choice. Null [value] means deletion. [identity] is
/// the original action identity, used to ask the store to resolve its current
/// versions. The view must never be encoded as a persistence action.
final class ConflictVersion {
  const ConflictVersion._(
    this._original,
    this.identity,
    this.value,
    this.device,
    this.savedAt,
  );
  // Used only for equality. Recovery can replace an action from the server
  // under the same identity, including fields this build does not interpret.
  // This detached copy is private; resolution always rereads the journal.
  final Map<String, dynamic> _original;
  final String identity;
  final RecordValue? value;

  /// The trimmed device name, or null when no readable name was saved.
  final String? device;

  /// When the action was saved, falling back to the bookmark or history time
  /// for legacy actions. Null when neither time can be read.
  final DateTime? savedAt;

  // Preserve the journal's content comparison, including map-order independence.
  // Reallocating an unchanged view must not notify, but a repaired copy must.
  @override
  bool operator ==(Object other) =>
      other is ConflictVersion &&
      identity == other.identity &&
      const DeepCollectionEquality().equals(_original, other._original);
  @override
  int get hashCode => identity.hashCode;
}

/// Supported conflicts, in journal order. Both collection levels and their
/// typed values are immutable and detached from the journal.
typedef RecordConflicts = Map<RecordAddress, List<ConflictVersion>>;

/// Projects already validated journal versions. A conflict containing any
/// unreadable future value is retained by the journal but has no choices.
RecordConflicts recordConflicts(
  Map<String, List<Map<String, dynamic>>> conflicts,
) {
  final result = <RecordAddress, List<ConflictVersion>>{};
  for (final entry in conflicts.entries) {
    final address = RecordAddress.parse(entry.key);
    if (!entry.value.every(
      (action) =>
          readableRecord(address, action['value'] as Map<String, dynamic>?),
    )) {
      continue;
    }
    result[address] = List.unmodifiable(
      entry.value.map((source) {
        // The view owns this copy even when its caller retains mutable inputs.
        final action = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
        final value = _decodeRecordValue(
          address,
          action['value'] as Map<String, dynamic>?,
        );
        final device = action['device'];
        final original = action['value'] as Map<String, dynamic>?;
        DateTime? savedAt;
        for (final at in [
          action['savedAt'],
          original?['createdAt'],
          original?['at'],
        ]) {
          if (at is String) savedAt = DateTime.tryParse(at);
          if (savedAt != null) break;
        }
        return ConflictVersion._(
          action,
          RecordJournal.identity(action),
          value,
          device is String && device.trim().isNotEmpty ? device.trim() : null,
          savedAt,
        );
      }),
    );
  }
  return Map.unmodifiable(result);
}

RecordValue? _decodeRecordValue(
  RecordAddress address,
  Map<String, dynamic>? value,
) {
  if (value == null) return null;
  final reading = address.domain == 'reading';
  final decodePlace = reading ? decodeTextPosition : decodePosition;
  try {
    switch (address.collection) {
      case 'bookmarks':
        if (value['id'] != address.id) throw const FormatException();
        return BookmarkValue(Bookmark.fromJson(value, decodePlace));
      case 'history':
        if (value['id'] != address.id) throw const FormatException();
        return HistoryValue(HistoryEvent.fromJson(value, decodePlace));
      case 'resumes':
        final position = decodePlace(value);
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
        ).containsKey(address.encoded)) {
          throw const FormatException();
        }
        return ResumeValue(
          position,
          value['bookTitle'] is String ? value['bookTitle'] as String : null,
        );
      default:
        throw const FormatException();
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
        : (Map.of(metadata)
            ..remove('reading')
            ..remove('retainedObjects')),
    'bookmarks': <dynamic>[],
    'history': <dynamic>[],
    'resumes': reading ? <dynamic>[] : <String, dynamic>{},
  };
  for (final entry in values.entries) {
    final address = RecordAddress.parse(entry.key);
    if (address.domain != domain || !readableRecord(address, entry.value)) {
      continue;
    }
    final collection = address.collection;
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
      result[_recordAddress(domain, collection, value['id'])] =
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
      result[_recordAddress(domain, 'resumes', address)] =
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
        result[_recordAddress(domain, 'resumes', address)] = {
          ...value,
          'edition': entry.key,
        };
      }
    }
  }
  return result;
}

/// The journal records changed by a writer's detached change set, including
/// null values for deleted bookmarks and history entries. Values remain owned
/// by [changes]. Resumes use the same current and legacy formats as snapshots.
Map<String, Map<String, dynamic>?> recordChanges(
  Map<String, dynamic> changes, {
  required bool reading,
}) {
  final domain = reading ? 'reading' : 'audio';
  // NOTE: Keep each writer's existing collection order: it determines the
  // sequence of the journal actions created for one save.
  final collections = reading
      ? ['bookmarks', 'history']
      : ['history', 'bookmarks'];
  final resumes = {'resumes': changes['resumes']};
  return {
    for (final collection in collections)
      for (final entry in (changes[collection] as Map).entries)
        _recordAddress(domain, collection, entry.key):
            entry.value as Map<String, dynamic>?,
    ...flattenRecords(
      reading ? {'reading': resumes} : resumes,
      reading: reading,
    ),
  };
}

/// A bookmark record preserving [resume] in its [domain], keyed by its journal
/// address. Listening bookmarks contain the position fields only; reading
/// bookmarks retain the complete resume value.
MapEntry<String, Map<String, dynamic>> resumeBookmarkRecord(
  String domain,
  Map<String, dynamic> resume, {
  required String id,
  required DateTime createdAt,
  required String title,
}) {
  final audio = domain == 'audio';
  return MapEntry(_recordAddress(domain, 'bookmarks', id), {
    'id': id,
    'position': audio
        ? {
            'edition': resume['edition'],
            'source': resume['source'],
            'revision': resume['revision'],
            'milliseconds': resume['milliseconds'],
          }
        : Map<String, dynamic>.from(resume),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'title': title,
    if (audio) 'bookTitle': 'Saved listening place',
    if (audio) 'editionLabel': 'Saved recording',
  });
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
  return _recordAddress(
    reading ? 'reading' : 'audio',
    'resumes',
    reading
        ? jsonEncode([
            edition.id,
            edition.files.single.key,
            edition.files.single.revision,
          ])
        : jsonEncode([edition.id, editionSources(edition)]),
  );
}
