import 'package:flutter/foundation.dart';

/// A value that [read] computes from a source each time it is read. It
/// keeps no copy and no listeners of its own: a listener goes to [changes],
/// which must notify whenever [read] can return something new.
///
/// An owner that rebuilds makes a new one each time. Give the owner's
/// [source] to keep the old subscription: two values of one type with equal
/// sources are equal, so a [ValueListenableBuilder] keeps its listener.
/// Give the same source only to values that read the same thing. Without a
/// source, a value equals only itself.
class DerivedValue<T> implements ValueListenable<T> {
  DerivedValue(this.changes, this.read, {this.source});

  /// Notifies when the value can change.
  final Listenable changes;

  /// Computes the value from the source. It runs at each read, so it must
  /// be cheap or cached by the source.
  final T Function() read;

  /// What the value is read from, which decides equality, or null.
  final Object? source;

  @override
  T get value => read();

  @override
  void addListener(VoidCallback listener) => changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      changes.removeListener(listener);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      source != null &&
          other is DerivedValue<T> &&
          other.runtimeType == runtimeType &&
          other.source == source;

  @override
  int get hashCode =>
      source == null ? identityHashCode(this) : Object.hash(T, source);
}
