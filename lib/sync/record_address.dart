import 'dart:convert';

/// A journal key with named parts. Equality and [encoded] retain the exact
/// input, including whitespace and escapes: legacy encodings are distinct
/// journal keys even when their parts match. Unknown domains and collections
/// remain valid, so newer records can pass through an older journal.
final class RecordAddress {
  const RecordAddress._(this.encoded, this.domain, this.collection, this.id);

  /// Reads three nonempty strings, or throws [FormatException].
  factory RecordAddress.parse(String encoded) {
    final parts = jsonDecode(encoded);
    if (parts is! List ||
        parts.length != 3 ||
        parts.any((part) => part is! String || part.isEmpty)) {
      throw const FormatException('Invalid personal-record address.');
    }
    return RecordAddress._(encoded, parts[0], parts[1], parts[2]);
  }

  /// Creates a new key in the existing wire format. Use [RecordAddress.parse]
  /// for an existing key, so its identity is never normalized.
  factory RecordAddress(String domain, String collection, String id) {
    if (domain.isEmpty || collection.isEmpty || id.isEmpty) {
      throw const FormatException('Invalid personal-record address.');
    }
    return RecordAddress._(
      jsonEncode([domain, collection, id]),
      domain,
      collection,
      id,
    );
  }

  final String encoded;
  final String domain;
  final String collection;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is RecordAddress && encoded == other.encoded;
  @override
  int get hashCode => encoded.hashCode;
  @override
  String toString() => encoded;
}
