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
}
