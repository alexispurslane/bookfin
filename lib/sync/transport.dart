import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../catalog/jellyfin.dart';
import '../playback/store.dart';
import 'journal.dart';

/// How many of this phone's saved actions differed from the server's copy
/// of the same action and were replaced by it during one exchange.
typedef SyncReport = ({int replaced});

typedef _UploadResult = ({
  String identity,
  Map<String, dynamic>? copy,
  Exception? error,
  StackTrace? stack,
});

/// The Bookfin plugin protocol: validates replies and exchanges immutable
/// actions. The store owns durability, acknowledgments, cursor updates and
/// damaged-copy replacement. This module never mutates a journal directly.
class RecordTransport {
  RecordTransport(this.records);
  final LocalResumeStore records;

  /// Uploads the pending actions of the account of [session], then receives
  /// the actions that other devices uploaded, and saves each page of them
  /// with its discovery cursor in one write.
  Future<SyncReport> synchronize(
    JellyfinSession session,
    JellyfinClient client,
  ) async {
    await client.validate(session);
    final account = session.scope.key;
    var replaced = 0;
    final after = await records.discoveryCursor(account);
    final first = await client.personalRecordChanges(session, after);
    // Negotiate only from an authenticated, structurally valid legacy page.
    // A failed request or a malformed version never means an old plugin.
    final firstPage = await compute(_decodePage, (page: first, after: after));
    final batch = _supportsBatches(first);
    final pending = await records.pendingUploads(account);
    final uploads = pending.isEmpty
        ? <_Upload>[]
        : await compute(_encodeUploads, pending);
    for (var start = 0; start < uploads.length;) {
      var end = start;
      var bytes = 0;
      final count = batch ? 256 : 4;
      while (end < uploads.length && end - start < count) {
        final next = uploads[end].bytes;
        if (end > start && bytes + next > 1048576) break;
        bytes += next;
        end++;
      }
      final group = uploads.sublist(start, end);
      final results = batch
          ? await _uploadBatch(session, client, group)
          : await Future.wait([
              for (final upload in group) _upload(session, client, upload),
            ]);
      start = end;
      replaced += await records.takeServerCopies(account, [
        for (final result in results) ?result.copy,
      ]);
      await records.acknowledgeBatch(account, [
        for (final result in results)
          if (result.error == null) result.identity,
      ]);
      for (final result in results) {
        if (result.error case final error?) {
          Error.throwWithStackTrace(error, result.stack!);
        }
      }
    }
    for (var request = 0; request < 128; request++) {
      final after = await records.discoveryCursor(account);
      final page = request == 0 && uploads.isEmpty
          ? firstPage
          : await compute(_decodePage, (
              page: batch
                  ? await client.personalRecordBatchChanges(session, after)
                  : await client.personalRecordChanges(session, after),
              after: after,
            ));
      final actions = page.actions;
      replaced += await records.takeServerCopies(account, actions);
      await records.receivePage(account, actions, page.cursor);
      if (!page.hasMore) {
        return (replaced: replaced);
      }
    }
    throw Exception(
      'Personal-record sync is incomplete. Retry to continue discovery.',
    );
  }

  Future<_UploadResult> _upload(
    JellyfinSession session,
    JellyfinClient client,
    _Upload upload,
  ) async {
    final identity = upload.identity;
    try {
      final payload = upload.payload;
      Map<String, dynamic> stored;
      try {
        stored = await client.uploadPersonalRecord(session, identity, payload);
      } on Exception {
        // Only an independently verified server copy recovers a failed PUT.
        final copy = await _serverCopy(session, client, identity);
        if (copy == null) rethrow;
        return (identity: identity, copy: copy, error: null, stack: null);
      }
      _verifyConfirmation(upload, stored);
      return (identity: identity, copy: null, error: null, stack: null);
    } on Exception catch (error, stack) {
      return (identity: identity, copy: null, error: error, stack: stack);
    }
  }

  Future<List<_UploadResult>> _uploadBatch(
    JellyfinSession session,
    JellyfinClient client,
    List<_Upload> uploads,
  ) async {
    // If the whole response is interrupted, no item is confirmed. Retrying
    // the immutable objects is safe, even when the server committed them.
    final reply = await client.uploadPersonalRecords(session, [
      for (final upload in uploads)
        {'Id': upload.identity, 'Payload': upload.payload},
    ]);
    final results = await compute(_batchConfirmations, (
      uploads: uploads,
      reply: reply,
    ));
    // Damaged copies are rare, but a damaged group must not fan out into
    // hundreds of simultaneous reads either.
    for (var start = 0; start < results.length; start += 4) {
      final recovered = await Future.wait([
        for (final result in results.skip(start).take(4))
          if (result.error case CatalogFailure(status: 409))
            _recoverConflict(session, client, result)
          else
            Future.value(result),
      ]);
      results.setRange(start, start + recovered.length, recovered);
    }
    return results;
  }

  Future<_UploadResult> _recoverConflict(
    JellyfinSession session,
    JellyfinClient client,
    _UploadResult result,
  ) async {
    final copy = await _serverCopy(session, client, result.identity);
    return copy == null
        ? result
        : (identity: result.identity, copy: copy, error: null, stack: null);
  }

  /// The server's copy of the action [identity], or null when the server
  /// cannot be asked, lacks it, or answers with something else.
  Future<Map<String, dynamic>?> _serverCopy(
    JellyfinSession session,
    JellyfinClient client,
    String identity,
  ) async {
    try {
      final stored = await client.personalRecord(session, identity);
      if (stored['Id'] != identity ||
          stored['Deleted'] != false ||
          stored['Sequence'] is! int ||
          (stored['Sequence'] as int) < 1 ||
          stored['Payload'] is! String) {
        return null;
      }
      final copy = jsonDecode(stored['Payload'] as String);
      return copy is Map<String, dynamic> &&
              RecordJournal.identity(copy) == identity
          ? copy
          : null;
    } on Exception {
      return null;
    }
  }
}

/// Encoded once off the UI isolate; bytes count the opaque payload's UTF-8.
typedef _Upload = ({String identity, String payload, int bytes});
typedef _Page = ({
  List<Map<String, dynamic>> actions,
  int cursor,
  bool hasMore,
});

List<_Upload> _encodeUploads(List<Map<String, dynamic>> actions) => [
  for (final action in actions) _encodeUpload(action),
];

_Upload _encodeUpload(Map<String, dynamic> action) {
  final payload = jsonEncode(action);
  final bytes = utf8.encode(payload).length;
  if (bytes > 65536) {
    throw const FormatException(
      'A personal-record upload exceeds the storage contract.',
    );
  }
  return (
    identity: RecordJournal.identity(action),
    payload: payload,
    bytes: bytes,
  );
}

bool _supportsBatches(Map<String, dynamic> page) {
  if (!page.containsKey('PluginVersion')) return false;
  final version = page['PluginVersion'];
  if (version is! String || !RegExp(r'^0\.\d+\.\d+\.\d+$').hasMatch(version)) {
    throw const FormatException('Unsupported Bookfin Storage plugin version.');
  }
  final minor = int.tryParse(version.split('.')[1]);
  if (minor == null) throw const FormatException('Invalid plugin version.');
  return minor >= 2;
}

void _verifyConfirmation(_Upload upload, Map<String, dynamic> stored) {
  if (stored['Id'] != upload.identity ||
      stored['Payload'] != upload.payload ||
      stored['Deleted'] != false ||
      stored['Sequence'] is! int ||
      (stored['Sequence'] as int) < 1) {
    throw const FormatException(
      'The server did not confirm the pending personal record.',
    );
  }
}

List<_UploadResult> _batchConfirmations(
  ({List<_Upload> uploads, Map<String, dynamic> reply}) input,
) {
  final values = input.reply['Results'];
  if (values is! List) {
    throw const FormatException('Invalid personal-record batch response.');
  }
  final expected = {for (final upload in input.uploads) upload.identity};
  final byIdentity = <String, List<Map<String, dynamic>>>{};
  for (final value in values) {
    if (value is! Map<String, dynamic> ||
        value['Id'] is! String ||
        !expected.contains(value['Id'])) {
      throw const FormatException('Unexpected personal-record batch identity.');
    }
    byIdentity.putIfAbsent(value['Id'] as String, () => []).add(value);
  }
  return [
    for (final upload in input.uploads)
      _batchConfirmation(upload, byIdentity[upload.identity]),
  ];
}

_UploadResult _batchConfirmation(
  _Upload upload,
  List<Map<String, dynamic>>? values,
) {
  try {
    if (values == null || values.length != 1) {
      throw const FormatException(
        'Missing or repeated personal-record confirmation.',
      );
    }
    final value = values.single;
    if (value['Status'] == 409 || value['Status'] == 410) {
      throw CatalogFailure(
        CatalogFailureKind.unavailable,
        status: value['Status'] as int,
      );
    }
    if (value['Status'] is! int ||
        (value['Status'] != 200 && value['Status'] != 201) ||
        value['Object'] is! Map<String, dynamic>) {
      throw const FormatException(
        'Invalid personal-record confirmation status.',
      );
    }
    _verifyConfirmation(upload, value['Object'] as Map<String, dynamic>);
    return (identity: upload.identity, copy: null, error: null, stack: null);
  } on Exception catch (error, stack) {
    return (identity: upload.identity, copy: null, error: error, stack: stack);
  }
}

_Page _decodePage(({Map<String, dynamic> page, int after}) input) {
  final page = input.page;
  if (page['Objects'] is! List ||
      page['Cursor'] is! int ||
      page['HasMore'] is! bool) {
    throw const FormatException('Invalid personal-record discovery response.');
  }
  final objects = page['Objects'] as List;
  if (objects.length > 256) {
    throw const FormatException('Oversized discovery page.');
  }
  var previous = input.after;
  var bytes = 0;
  final actions = <Map<String, dynamic>>[];
  for (final value in objects) {
    if (value is! Map<String, dynamic> ||
        value['Sequence'] is! int ||
        (value['Sequence'] as int) <= previous ||
        value['Deleted'] != false ||
        value['Payload'] is! String) {
      throw const FormatException(
        'Personal-record discovery is incomplete or contains retired actions.',
      );
    }
    previous = value['Sequence'] as int;
    bytes += utf8.encode(value['Payload'] as String).length;
    if (bytes > 1048576) {
      throw const FormatException('Oversized discovery page.');
    }
    final decoded = jsonDecode(value['Payload'] as String);
    if (decoded is! Map<String, dynamic> ||
        value['Id'] != RecordJournal.identity(decoded)) {
      throw const FormatException('Invalid personal-record object identity.');
    }
    actions.add(decoded);
  }
  if (page['Cursor'] != previous ||
      (page['HasMore'] == true && objects.isEmpty)) {
    throw const FormatException(
      'Personal-record discovery did not advance safely.',
    );
  }
  return (actions: actions, cursor: previous, hasMore: page['HasMore'] as bool);
}
