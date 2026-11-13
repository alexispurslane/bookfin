import 'dart:convert';

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
    final uploads = await records.pendingUploads(account);
    // A group bounds in-flight requests and local commits. Completion order
    // carries no causal meaning: the journal applies each action's context.
    for (var start = 0; start < uploads.length; start += 4) {
      final results = await Future.wait([
        for (final action in uploads.skip(start).take(4))
          _upload(session, client, action),
      ]);
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
      final page = await client.personalRecordChanges(session, after);
      if (page['Objects'] is! List ||
          page['Cursor'] is! int ||
          page['HasMore'] is! bool) {
        throw const FormatException(
          'Invalid personal-record discovery response.',
        );
      }
      final objects = page['Objects'] as List;
      var previous = after;
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
        final decoded = jsonDecode(value['Payload'] as String);
        if (decoded is! Map<String, dynamic> ||
            value['Id'] != RecordJournal.identity(decoded)) {
          throw const FormatException(
            'Invalid personal-record object identity.',
          );
        }
        actions.add(decoded);
      }
      replaced += await records.takeServerCopies(account, actions);
      if (page['Cursor'] != previous ||
          (page['HasMore'] == true && objects.isEmpty)) {
        throw const FormatException(
          'Personal-record discovery did not advance safely.',
        );
      }
      await records.receivePage(account, actions, previous);
      if (page['HasMore'] == false) {
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
    Map<String, dynamic> action,
  ) async {
    final identity = RecordJournal.identity(action);
    try {
      final payload = jsonEncode(action);
      Map<String, dynamic> stored;
      try {
        stored = await client.uploadPersonalRecord(session, identity, payload);
      } on Exception {
        // Only an independently verified server copy recovers a failed PUT.
        final copy = await _serverCopy(session, client, identity);
        if (copy == null) rethrow;
        return (identity: identity, copy: copy, error: null, stack: null);
      }
      if (stored['Id'] != identity ||
          stored['Payload'] != payload ||
          stored['Deleted'] != false ||
          stored['Sequence'] is! int ||
          (stored['Sequence'] as int) < 1) {
        throw const FormatException(
          'The server did not confirm the pending personal record.',
        );
      }
      return (identity: identity, copy: null, error: null, stack: null);
    } on Exception catch (error, stack) {
      return (identity: identity, copy: null, error: error, stack: stack);
    }
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
