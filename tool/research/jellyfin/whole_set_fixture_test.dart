import 'package:flutter_test/flutter_test.dart';

import 'whole_set_fixture.dart';

void main() {
  test(
    'the whole-set fixture exposes loss despite merging each stale read',
    () async {
      final result = await runCounterexamples();
      expect(result['readMergeWrite'], {
        'acknowledgedWrites': 2,
        'remainingRecordIds': ['bookmark-b'],
        'lostRecordIds': ['bookmark-a'],
      });
    },
  );

  test('separate device partitions still lose device discovery', () async {
    final result = await runCounterexamples();
    expect(result['partitionDiscovery'], {
      'storedDevicePartitions': 2,
      'discoverableDeviceIds': ['device-b'],
      'undiscoverableDeviceIds': ['device-a'],
    });
  });

  test(
    'a stale retry can resurrect a record after its deletion was acknowledged',
    () async {
      final result = await runCounterexamples();
      expect(result['staleRetryAfterDeletion'], {
        'deletedBeforeRetry': true,
        'resurrectedAfterRetry': true,
        'tombstoneLost': true,
      });
    },
  );

  test(
    'fixture reopening preserves scopes and bounded synthetic values',
    () async {
      final result = await runCounterexamples();
      expect(result['fixtureReopen'], {
        'acceptedValueBytes': [1024, 4096, 16384],
        'separateUsers': true,
        'separateItems': true,
        'separateClients': true,
        'identicalRetry': true,
        'removedKeyStaysAbsent': true,
      });
    },
  );
}
