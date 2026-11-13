import 'package:flutter/foundation.dart';

/// A domain's durable store that coordinates its live writers. Playback and
/// the reader register at construction and unregister when closed/disposed.
/// An in-memory store without sync need not implement this interface.
abstract interface class RecordWriterHost {
  /// Registers the writer once. [account] returns its current account, or
  /// null while signed out. Sync flushes every registered writer before an
  /// exchange or choice, and refreshes only stale writers of its account
  /// after an exchange, choice, or recovery of kept records.
  ///
  /// The returned callback unregisters this writer and is safe to repeat.
  VoidCallback registerWriter({
    required String? Function() account,
    required Future<void> Function() flush,
    required Future<void> Function() refresh,
  });

  /// Whether this domain of [account] changed outside its writer since the
  /// last snapshot it accepted. A failed refresh leaves this signal true.
  ValueListenable<bool> staleNotifier(String account);
}
