import 'package:bookfin/downloads/downloads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote media waits for known Wi-Fi but complete files stay local', () {
    final policy = MediaPolicy();
    expect(policy.choose(verifiedLocal: false), MediaLocation.blocked);
    for (final network in MediaNetwork.values) {
      policy.network = network;
      expect(policy.choose(verifiedLocal: true), MediaLocation.local);
      expect(
        policy.choose(verifiedLocal: false),
        network == MediaNetwork.wifi
            ? MediaLocation.remote
            : MediaLocation.blocked,
      );
    }
  });
  test('mobile permission lasts only for this account session', () {
    final policy = MediaPolicy()..network = MediaNetwork.mobile;
    policy.allowMobileForSession();
    expect(policy.choose(verifiedLocal: false), MediaLocation.remote);
    policy.network = MediaNetwork.unknown;
    expect(policy.choose(verifiedLocal: false), MediaLocation.blocked);
    policy.network = MediaNetwork.mobile;
    policy.resetSession();
    expect(policy.choose(verifiedLocal: false), MediaLocation.blocked);
  });

  group('download actions', () {
    List<DownloadAction> actions(
      DownloadPhase phase, {
      int bytes = 0,
      int unavailableBytes = 0,
      int completeFiles = 0,
    }) => EditionDownload(
      phase: phase,
      bytes: bytes,
      unavailableBytes: unavailableBytes,
      completeFiles: completeFiles,
    ).actions;

    test('a running or waiting transfer can only be canceled', () {
      expect(actions(DownloadPhase.downloading, bytes: 5), [
        DownloadAction.cancel,
      ]);
      expect(actions(DownloadPhase.waiting, bytes: 5), [DownloadAction.cancel]);
    });

    test('a finished download can only be removed', () {
      expect(actions(DownloadPhase.downloaded), [DownloadAction.remove]);
    });

    test('a failure or saved bytes are retried before they are removed', () {
      expect(actions(DownloadPhase.failed), [
        DownloadAction.retry,
        DownloadAction.remove,
      ]);
      expect(actions(DownloadPhase.partial, bytes: 1), [
        DownloadAction.retry,
        DownloadAction.remove,
      ]);
    });

    test('nothing saved is downloaded, and unusable files can go', () {
      expect(actions(DownloadPhase.none), [DownloadAction.request]);
      expect(actions(DownloadPhase.none, unavailableBytes: 1), [
        DownloadAction.request,
        DownloadAction.remove,
      ]);
      expect(actions(DownloadPhase.partial, completeFiles: 1), [
        DownloadAction.request,
        DownloadAction.remove,
      ]);
    });
  });
}
