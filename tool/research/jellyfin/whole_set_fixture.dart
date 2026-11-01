import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>> runCounterexamples() async {
  final directory = await Directory.systemTemp.createTemp('bookfin-whole-set-');
  final file = File('${directory.path}/synthetic.json');
  file.writeAsStringSync('{}');
  Map<String, String> read(String user, String item, String client) {
    final database = jsonDecode(file.readAsStringSync()) as Map;
    return Map<String, String>.from(
      database[jsonEncode([user, item, client])] as Map? ?? {},
    );
  }

  void replace(
    String user,
    String item,
    String client,
    Map<String, String> values,
  ) {
    final database = jsonDecode(file.readAsStringSync()) as Map;
    database[jsonEncode([user, item, client])] = values;
    file.writeAsStringSync(jsonEncode(database));
  }

  try {
    final firstRead = read('user-a', 'shared-bookmarks', 'bookfin');
    final secondRead = read('user-a', 'shared-bookmarks', 'bookfin');
    replace('user-a', 'shared-bookmarks', 'bookfin', {
      ...firstRead,
      'bookmark-a': 'first',
    });
    replace('user-a', 'shared-bookmarks', 'bookfin', {
      ...secondRead,
      'bookmark-b': 'second',
    });
    final bookmarks = read('user-a', 'shared-bookmarks', 'bookfin');

    final firstRegistry = read('user-a', 'device-registry', 'bookfin');
    final secondRegistry = read('user-a', 'device-registry', 'bookfin');
    replace('user-a', 'records', 'device-a', {'bookmark-a': 'first'});
    replace('user-a', 'records', 'device-b', {'bookmark-b': 'second'});
    replace('user-a', 'device-registry', 'bookfin', {
      ...firstRegistry,
      'device-a': 'registered',
    });
    replace('user-a', 'device-registry', 'bookfin', {
      ...secondRegistry,
      'device-b': 'registered',
    });
    final registry = read('user-a', 'device-registry', 'bookfin');

    replace('user-a', 'deletion', 'bookfin', {'bookmark-a': 'revision-1'});
    final retryPayload = read('user-a', 'deletion', 'bookfin');
    replace('user-a', 'deletion', 'bookfin', {
      'deleted:bookmark-a': 'revision-2',
    });
    final deleted = !read(
      'user-a',
      'deletion',
      'bookfin',
    ).containsKey('bookmark-a');
    replace('user-a', 'deletion', 'bookfin', retryPayload);
    final afterRetry = read('user-a', 'deletion', 'bookfin');

    final accepted = <int>[];
    for (final size in [1024, 4096, 16384]) {
      replace('user-a', 'sizes', 'bookfin', {'payload': 'x' * size});
      if (read('user-a', 'sizes', 'bookfin')['payload'] == 'x' * size) {
        accepted.add(size);
      }
    }
    replace('user-b', 'sizes', 'bookfin', {'payload': 'other-user'});
    replace('user-a', 'other-item', 'bookfin', {'payload': 'other-item'});
    replace('user-a', 'sizes', 'other-client', {'payload': 'other-client'});
    final beforeRetry = read('user-a', 'sizes', 'bookfin');
    replace('user-a', 'sizes', 'bookfin', beforeRetry);
    final identicalRetry =
        jsonEncode(read('user-a', 'sizes', 'bookfin')) ==
        jsonEncode(beforeRetry);
    replace('user-a', 'sizes', 'bookfin', {});

    final staleReads = List.generate(
      32,
      (_) => read('user-a', 'scheduled-writers', 'bookfin'),
    );
    for (var index = 0; index < staleReads.length; index++) {
      replace('user-a', 'scheduled-writers', 'bookfin', {
        ...staleReads[index],
        'writer-$index': 'synthetic',
      });
    }
    final remaining = read('user-a', 'scheduled-writers', 'bookfin');
    return {
      'evidenceClass': 'local-file-backed-whole-set-model-not-jellyfin',
      'readMergeWrite': {
        'acknowledgedWrites': 2,
        'remainingRecordIds': bookmarks.keys.toList(),
        'lostRecordIds': [
          'bookmark-a',
          'bookmark-b',
        ].where((key) => !bookmarks.containsKey(key)).toList(),
      },
      'partitionDiscovery': {
        'storedDevicePartitions': ['device-a', 'device-b']
            .where((client) => read('user-a', 'records', client).isNotEmpty)
            .length,
        'discoverableDeviceIds': registry.keys.toList(),
        'undiscoverableDeviceIds': [
          'device-a',
          'device-b',
        ].where((key) => !registry.containsKey(key)).toList(),
      },
      'staleRetryAfterDeletion': {
        'deletedBeforeRetry': deleted,
        'resurrectedAfterRetry': afterRetry.containsKey('bookmark-a'),
        'tombstoneLost': !afterRetry.containsKey('deleted:bookmark-a'),
      },
      'fixtureReopen': {
        'acceptedValueBytes': accepted,
        'separateUsers':
            read('user-b', 'sizes', 'bookfin')['payload'] == 'other-user',
        'separateItems':
            read('user-a', 'other-item', 'bookfin')['payload'] == 'other-item',
        'separateClients':
            read('user-a', 'sizes', 'other-client')['payload'] ==
            'other-client',
        'identicalRetry': identicalRetry,
        'removedKeyStaysAbsent': read('user-a', 'sizes', 'bookfin').isEmpty,
      },
      'scheduledStaleWriters': {
        'acknowledgedWrites': staleReads.length,
        'remainingRecords': remaining.length,
        'lostRecords': staleReads.length - remaining.length,
        'schedule': 'all reads, then serialized writes; no real concurrent server requests',
      },
    };
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<void> main() async {
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert(await runCounterexamples()),
  );
}
