import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'downloads.dart';
import 'local_downloads.dart';
import 'platform_stub.dart' show UnavailableDownloads;

/// The media host contract that each platform's runner implements: the
/// Android activity, and the Apple runners' MediaChannel.swift. `storage`
/// names the private download directory, `freeBytes` the space left on its
/// volume, and `network` the current [MediaNetwork] by name, which
/// `bookfin/media-network` also sends on each change.
const _methods = MethodChannel('bookfin/media');
const _events = EventChannel('bookfin/media-network');

/// Opens downloads in the directory that the runner names. A runner without
/// the media host contract, such as a desktop port that does not implement
/// it yet, gives unavailable downloads.
Future<Downloads> createDownloads(MediaPolicy policy) async {
  try {
    final info = await _methods.invokeMapMethod<String, dynamic>('storage');
    if (info == null || info['path'] is! String) {
      return UnavailableDownloads(policy);
    }
    return _HostDownloads(Directory(info['path'] as String), policy);
  } catch (_) {
    policy.network = MediaNetwork.unknown;
    return UnavailableDownloads(policy);
  }
}

class _HostDownloads extends LocalDownloads {
  _HostDownloads(Directory directory, MediaPolicy policy)
    : super(
        root: directory,
        freeBytes: () async =>
            await _methods.invokeMethod<int>('freeBytes') ?? 0,
        policy: policy,
      ) {
    _subscription = _events.receiveBroadcastStream().listen(
      (value) => _acceptNetwork(value),
      onError: (Object _) => _acceptNetwork(null),
      onDone: () => _acceptNetwork(null),
    );
  }
  late final StreamSubscription<dynamic> _subscription;
  bool _closed = false;

  void _acceptNetwork(Object? value) {
    if (!_closed) {
      policy.network = MediaNetwork.values.firstWhere(
        (network) => network.name == value,
        orElse: () => MediaNetwork.unknown,
      );
    }
  }

  @override
  Future<void> refresh() async {
    try {
      _acceptNetwork(await _methods.invokeMethod<String>('network'));
    } catch (_) {
      _acceptNetwork(null);
    }
    await super.refresh();
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
