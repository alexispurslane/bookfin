import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MediaFixture fixture;
  late Directory root;
  late MediaPolicy policy;
  late LocalDownloads downloads;
  var capacity = 1000000;
  setUp(() async {
    fixture = await MediaFixture.start();
    root = await Directory.systemTemp.createTemp('bookfin-download-test-');
    policy = MediaPolicy()..network = MediaNetwork.wifi;
    capacity = 1000000;
    downloads = LocalDownloads(
      root: root,
      freeBytes: () async => capacity,
      policy: policy,
    );
    await downloads.bind(fixture.session(), fixture.books);
  });
  tearDown(() async {
    downloads.dispose();
    await downloads.idle;
    policy.dispose();
    await fixture.close();
    await root.delete(recursive: true);
  });

  test(
    'original ebooks without media-source metadata download exact bytes',
    () async {
      capacity = 2 * 1024 * 1024;
      fixture.bookWithoutMediaSources = true;
      await downloads.bind(fixture.session(), fixture.books);
      final source = fixture.text.files.single;
      expect(source.mediaSourceId, isEmpty);
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(
        downloads.status(fixture.text).phase,
        DownloadPhase.downloaded,
        reason: downloads.status(fixture.text).message,
      );
      final local = await downloads.localFile(source);
      expect(local, isNotNull);
      expect(await File.fromUri(local!).readAsBytes(), [1, 2, 3, 4, 5, 6]);
    },
  );

  test('fresh missing download permission blocks before media HTTP', () async {
    fixture.allowDownload = null;
    await downloads.request(fixture.text);
    await downloads.idle;
    expect(downloads.status(fixture.text).phase, DownloadPhase.failed);
    expect(fixture.mediaRequests, isEmpty);
    expect(await downloads.localFile(fixture.text.files.single), isNull);
  });

  test(
    'audio without media-source metadata cannot use the ebook exception',
    () async {
      fixture.audioWithoutMediaSources = true;
      await downloads.bind(fixture.session(), fixture.books);
      await downloads.request(fixture.audio);
      await downloads.idle;
      expect(downloads.status(fixture.audio).phase, DownloadPhase.failed);
      expect(fixture.mediaRequests, isEmpty);
    },
  );

  for (final includeOriginal in [false, true]) {
    test(
      'a first-listed alternate source never receives the item original '
      '${includeOriginal ? 'beside another source' : 'as the only source'}',
      () async {
        fixture.textSources = [
          fixture.source('alternate-text'),
          if (includeOriginal) fixture.source('text'),
        ];
        await downloads.bind(fixture.session(), fixture.books);
        final selected = fixture.text.files.single;
        expect(selected.key, 'text:alternate-text');
        await downloads.request(fixture.text);
        await downloads.idle;
        expect(downloads.status(fixture.text).phase, DownloadPhase.failed);
        expect(await downloads.localFile(selected), isNull);
        expect(fixture.mediaRequests, isEmpty);
        expect(fixture.requests.map((request) => request.uri.path), [
          '/jellyfin/System/Info/Public',
          '/jellyfin/Users/Me',
          '/jellyfin/Items/text',
        ]);
      },
    );
  }

  test('a named media-source list cannot claim an unnamed original', () async {
    fixture.textSources = [
      {...fixture.source('text'), 'Id': ''},
    ];
    await downloads.bind(fixture.session(), fixture.books);
    final selected = fixture.text.files.single;
    await downloads.request(fixture.text);
    await downloads.idle;
    expect(downloads.status(fixture.text).phase, DownloadPhase.failed);
    expect(await downloads.localFile(selected), isNull);
    expect(fixture.mediaRequests, isEmpty);
  });

  test('a selected second source cannot downgrade to the original', () async {
    fixture.textSources = [
      fixture.source('text'),
      fixture.source('alternate-text'),
    ];
    final books = buildBooks([
      CatalogEntry.fromJson(fixture.dto('text'), libraryId: 'books'),
    ]);
    final alternate = books.single.editions.singleWhere(
      (edition) => edition.files.single.mediaSourceId == 'alternate-text',
    );
    await downloads.bind(fixture.session(), books);
    await downloads.request(alternate);
    await downloads.idle;
    expect(downloads.status(alternate).phase, DownloadPhase.failed);
    expect(await downloads.localFile(alternate.files.single), isNull);
    expect(fixture.mediaRequests, isEmpty);
    expect(fixture.requests.map((request) => request.uri.path), [
      '/jellyfin/System/Info/Public',
      '/jellyfin/Users/Me',
      '/jellyfin/Items/text',
    ]);
  });

  for (final denyAccount in [false, true]) {
    test('an ordinary account cannot download an alternate after '
        '${denyAccount ? 'account' : 'item'} policy refusal', () async {
      fixture.textSources = [fixture.source('alternate-text')];
      await downloads.bind(fixture.session(), fixture.books);
      final selected = fixture.text.files.single;
      fixture.allowDownload = !denyAccount;
      fixture.itemDownloadable = denyAccount;
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.failed);
      expect(await downloads.localFile(selected), isNull);
      expect(fixture.requests.map((request) => request.uri.path), [
        '/jellyfin/System/Info/Public',
        '/jellyfin/Users/Me',
        if (!denyAccount) '/jellyfin/Items/text',
      ]);
    });
  }

  test('a missing selected source never switches to its replacement', () async {
    final selected = fixture.text;
    fixture.textSources = [fixture.source('replacement-text')];
    await downloads.request(selected);
    await downloads.idle;
    expect(downloads.status(selected).phase, DownloadPhase.failed);
    expect(await downloads.localFile(selected.files.single), isNull);
    expect(fixture.mediaRequests, isEmpty);
  });

  test('a source removed during receipt is never published', () async {
    final selected = fixture.text;
    fixture.holdItem = 'text';
    await downloads.request(selected);
    await fixture.firstChunk.future;
    fixture.textSources = [fixture.source('replacement-text')];
    fixture.release();
    await downloads.idle;
    expect(downloads.status(selected).phase, DownloadPhase.failed);
    expect(await downloads.localFile(selected.files.single), isNull);
    expect(fixture.mediaRequests, ['text']);
  });

  test(
    'current authentication works when the server rejects legacy token headers',
    () async {
      fixture.requireModernAuthentication = true;
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    },
  );

  test(
    'replacement interruption never assigns new identity to old bytes',
    () async {
      fixture.interruptOnce = true;
      await downloads.request(fixture.text);
      await downloads.idle;
      downloads.dispose();
      await downloads.idle;
      var checks = 0;
      downloads = LocalDownloads(
        root: root,
        policy: policy,
        freeBytes: () async {
          if (++checks == 2) policy.network = MediaNetwork.disconnected;
          return capacity;
        },
      );
      await downloads.bind(fixture.session(), fixture.books);
      fixture.ignoreRange = true;
      fixture.etag = '"v2"';
      fixture.payload = [7, 8, 9, 10, 11, 12];
      await downloads.request(fixture.text);
      await downloads.idle;
      final manifests = await root
          .list(recursive: true)
          .where((e) => e.path.endsWith('/record.json'))
          .toList();
      var replacements = 0;
      for (final entry in manifests) {
        final data = jsonDecode(await File(entry.path).readAsString());
        if (data['etag'] == '"v2"') {
          replacements++;
          final partial = File('${entry.parent.path}/partial');
          expect(
            await partial.exists() ? await partial.length() : 0,
            0,
            reason:
                'New response identity must never cover the previous prefix',
          );
        }
      }
      expect(replacements, 1);
      downloads.dispose();
      await downloads.idle;
      downloads = LocalDownloads(
        root: root,
        policy: policy,
        freeBytes: () async => capacity,
      );
      await downloads.bind(fixture.session(), fixture.books);
      fixture.ignoreRange = false;
      policy.network = MediaNetwork.wifi;
      await downloads.idle;
      final local = await downloads.localFile(fixture.text.files.single);
      expect(local, isNotNull);
      expect(await File.fromUri(local!).readAsBytes(), [7, 8, 9, 10, 11, 12]);
    },
  );

  test('cancel is durable while another edition remains downloading', () async {
    fixture.holdItem = 'audio1';
    await downloads.request(fixture.audio);
    await fixture.firstChunk.future;
    await downloads.request(fixture.text);
    try {
      await downloads.cancel(fixture.text).timeout(const Duration(seconds: 2));
      final manifests = await root
          .list(recursive: true)
          .where((e) => e.path.endsWith('/record.json'))
          .toList();
      final states = await Future.wait(
        manifests.map(
          (e) async => jsonDecode(await File(e.path).readAsString()) as Map,
        ),
      );
      expect(
        states
            .where((s) => s['key'] == fixture.text.files.single.key)
            .single['requested'],
        false,
      );
      expect(downloads.status(fixture.audio).phase, DownloadPhase.downloading);
    } finally {
      fixture.release();
    }
  });

  for (final remove in [false, true]) {
    test(
      '${remove ? 'remove' : 'cancel'} waits for restored requests',
      () async {
        policy.network = MediaNetwork.disconnected;
        await downloads.request(fixture.text);
        downloads.dispose();
        await downloads.idle;
        downloads = LocalDownloads(
          root: root,
          policy: policy,
          freeBytes: () async => capacity,
        );
        final binding = downloads.bind(fixture.session(), fixture.books);
        await (remove
            ? downloads.remove(fixture.text)
            : downloads.cancel(fixture.text));
        await binding;
        expect(downloads.status(fixture.text).phase, DownloadPhase.none);
        policy.network = MediaNetwork.wifi;
        await downloads.idle;
        expect(fixture.mediaRequests, isEmpty);
      },
    );
  }

  test(
    'early file failure leaves later transfer active and cancellable',
    () async {
      fixture.denyItem = 'audio1';
      fixture.holdItem = 'audio2';
      await downloads.request(fixture.audio);
      await fixture.firstChunk.future;
      try {
        expect(
          downloads.status(fixture.audio).phase,
          DownloadPhase.downloading,
        );
        expect(downloads.status(fixture.audio).message, isNotNull);
        policy.network = MediaNetwork.disconnected;
        await downloads.idle;
        expect(downloads.status(fixture.audio).phase, DownloadPhase.waiting);
        await downloads.cancel(fixture.audio);
        expect(downloads.status(fixture.audio).phase, DownloadPhase.none);
      } finally {
        fixture.release();
      }
    },
  );

  test('a complete ebook does not make the audio edition downloaded', () async {
    await downloads.request(fixture.text);
    await downloads.idle;
    expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    expect(downloads.status(fixture.audio).phase, DownloadPhase.none);
    expect(
      await File.fromUri(
        (await downloads.localFile(fixture.text.files.single))!,
      ).readAsBytes(),
      [1, 2, 3, 4, 5, 6],
    );
    expect(
      fixture.requests.every(
        (request) =>
            !request.uri.hasQuery || !request.uri.query.contains('token'),
      ),
      isTrue,
    );
    expect(fixture.mediaTokens, everyElement('synthetic-token'));
    downloads.checkInvariants();
  });

  test(
    'one complete audio file is only a partial multi-file edition',
    () async {
      fixture.denyItem = 'audio2';
      await downloads.request(fixture.audio);
      await downloads.idle;
      final state = downloads.status(fixture.audio);
      expect(state.phase, DownloadPhase.failed);
      expect(state.completeFiles, 1);
      expect(await downloads.localFile(fixture.audio.files.first), isNotNull);
      expect(await downloads.localFile(fixture.audio.files.last), isNull);
      await downloads.cancel(fixture.audio);
      expect(downloads.status(fixture.audio).phase, DownloadPhase.partial);
      fixture.denyItem = null;
      await downloads.request(fixture.audio);
      await downloads.idle;
      expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
    },
  );

  test(
    'unknown and disconnected networks queue without opening media',
    () async {
      for (final network in [
        MediaNetwork.unknown,
        MediaNetwork.disconnected,
        MediaNetwork.mobile,
      ]) {
        policy.network = network;
        await downloads.request(fixture.audio);
        await downloads.idle;
        expect(downloads.status(fixture.audio).phase, DownloadPhase.waiting);
        expect(fixture.mediaRequests, isEmpty);
      }
      policy.network = MediaNetwork.wifi;
      await downloads.idle;
      expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
    },
  );

  test(
    'Wi-Fi loss interrupts remote bytes and waits until Wi-Fi returns',
    () async {
      fixture.holdItem = 'audio1';
      await downloads.request(fixture.audio);
      expect(downloads.status(fixture.audio).phase, DownloadPhase.downloading);
      await fixture.firstChunk.future;
      await waitForBytes(downloads, fixture.audio, 3);
      policy.network = MediaNetwork.mobile;
      await downloads.idle;
      expect(downloads.status(fixture.audio).phase, DownloadPhase.waiting);
      expect(await downloads.localFile(fixture.audio.files.first), isNull);
      fixture.release();
      fixture.holdItem = null;
      policy.network = MediaNetwork.wifi;
      await downloads.idle;
      expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
      expect(fixture.ranges, contains('bytes=3-'));
    },
  );

  test(
    'restart recovers an interrupted file with a matching range validator',
    () async {
      fixture.interruptOnce = true;
      await downloads.request(fixture.audio);
      await downloads.idle;
      expect(downloads.status(fixture.audio).phase, DownloadPhase.failed);
      downloads.dispose();
      await downloads.idle;
      downloads = LocalDownloads(
        root: root,
        freeBytes: () async => capacity,
        policy: policy,
      );
      await downloads.bind(fixture.session(), fixture.books);
      expect(await downloads.localFile(fixture.audio.files.first), isNull);
      await downloads.request(fixture.audio);
      await downloads.idle;
      expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
      expect(fixture.ranges, contains('bytes=3-'));
      expect(fixture.ifRanges, contains('"v1"'));
    },
  );

  test('invalid ranges never append untrusted bytes', () async {
    fixture.interruptOnce = true;
    await downloads.request(fixture.audio);
    await downloads.idle;
    fixture.invalidRange = true;
    await downloads.request(fixture.audio);
    await downloads.idle;
    expect(downloads.status(fixture.audio).phase, DownloadPhase.failed);
    expect(await downloads.localFile(fixture.audio.files.first), isNull);
    fixture.invalidRange = false;
    await downloads.request(fixture.audio);
    await downloads.idle;
    expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
  });

  test('a changed ETag discards the old prefix before retry', () async {
    fixture.interruptOnce = true;
    await downloads.request(fixture.audio);
    await downloads.idle;
    fixture.etag = '"v2"';
    await downloads.request(fixture.audio);
    await downloads.idle;
    expect(downloads.status(fixture.audio).phase, DownloadPhase.failed);
    expect(await downloads.localFile(fixture.audio.files.first), isNull);
    await downloads.request(fixture.audio);
    await downloads.idle;
    expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
  });

  test(
    'cancel prevents the next file and retry keeps completed files',
    () async {
      fixture.holdItem = 'audio2';
      await downloads.request(fixture.audio);
      expect(downloads.status(fixture.audio).phase, DownloadPhase.downloading);
      await fixture.firstChunk.future;
      await downloads.cancel(fixture.audio);
      await downloads.idle;
      expect(downloads.status(fixture.audio).phase, DownloadPhase.partial);
      expect(downloads.status(fixture.audio).completeFiles, 1);
      fixture.release();
      fixture.holdItem = null;
      await downloads.request(fixture.audio);
      await downloads.idle;
      expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
      expect(
        fixture.mediaRequests.where((item) => item == 'audio1'),
        hasLength(1),
      );
    },
  );

  test(
    'fresh permission and item downloadability deny even an administrator',
    () async {
      fixture.administrator = true;
      fixture.allowDownload = false;
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.failed);
      expect(fixture.mediaRequests, isEmpty);
      fixture.allowDownload = true;
      fixture.itemDownloadable = false;
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.failed);
      expect(fixture.mediaRequests, isEmpty);
    },
  );

  test('a denied Download never tries File or another route', () async {
    fixture.denyItem = 'text';
    await downloads.request(fixture.text);
    await downloads.idle;
    expect(downloads.status(fixture.text).phase, DownloadPhase.failed);
    expect(fixture.requests.map((request) => request.uri.path), [
      '/jellyfin/System/Info/Public',
      '/jellyfin/Users/Me',
      '/jellyfin/Items/text',
      '/jellyfin/Items/text/Download',
    ]);
    expect(fixture.mediaRequests, ['text']);
    expect(await downloads.localFile(fixture.text.files.single), isNull);
  });

  test('insufficient free space fails before media starts', () async {
    capacity = 1;
    await downloads.request(fixture.audio);
    await downloads.idle;
    expect(downloads.status(fixture.audio).phase, DownloadPhase.failed);
    expect(fixture.mediaRequests, isEmpty);
    capacity = 1000000;
    await downloads.request(fixture.audio);
    await downloads.idle;
    expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
  });

  test(
    'missing and corrupted local files lose their complete status',
    () async {
      await downloads.request(fixture.audio);
      await downloads.idle;
      expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
      final first = File.fromUri(
        (await downloads.localFile(fixture.audio.files.first))!,
      );
      await first.writeAsBytes([6, 5, 4, 3, 2, 1]);
      expect(await downloads.localFile(fixture.audio.files.first), isNull);
      expect(downloads.status(fixture.audio).phase, DownloadPhase.partial);
      final last = File.fromUri(
        (await downloads.localFile(fixture.audio.files.last))!,
      );
      await last.delete();
      expect(await downloads.localFile(fixture.audio.files.last), isNull);
      expect(downloads.status(fixture.audio).phase, DownloadPhase.none);
    },
  );

  test(
    'account switching hides old files and invalidates held callbacks',
    () async {
      fixture.holdItem = 'text';
      await downloads.request(fixture.text);
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloading);
      await fixture.firstChunk.future;
      await downloads.bind(fixture.session(user: 'bob'), fixture.books);
      fixture.release();
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.none);
      expect(await downloads.localFile(fixture.text.files.single), isNull);
      await downloads.bind(null, []);
      expect(await downloads.localFile(fixture.text.files.single), isNull);
      downloads.checkInvariants();
    },
  );

  test(
    'removal keeps unrelated files and survives account restoration',
    () async {
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
      final unrelated = await File('${root.path}/user-notes.txt')
          .writeAsString('keep');
      await downloads.remove(fixture.text);
      expect(await unrelated.readAsString(), 'keep');
      downloads.dispose();
      await downloads.idle;
      downloads = LocalDownloads(
        root: root,
        freeBytes: () async => capacity,
        policy: policy,
      );
      await downloads.bind(fixture.session(), fixture.books);
      expect(downloads.status(fixture.text).phase, DownloadPhase.none);
      expect(await downloads.localFile(fixture.text.files.single), isNull);
    },
  );

  test(
    'complete files survive restart but not a changed source revision',
    () async {
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
      downloads.dispose();
      await downloads.idle;
      downloads = LocalDownloads(
        root: root,
        freeBytes: () async => capacity,
        policy: policy,
      );
      await downloads.bind(fixture.session(), fixture.books);
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
      fixture.revision = 'source-v2';
      await downloads.bind(fixture.session(), fixture.books);
      expect(downloads.status(fixture.text).phase, DownloadPhase.none);
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    },
  );

  test(
    'a source changed on the server is not downloaded under its old revision',
    () async {
      final oldText = fixture.text;
      fixture.revision = 'source-v2';
      await downloads.request(oldText);
      await downloads.idle;
      expect(downloads.status(oldText).phase, DownloadPhase.failed);
      expect(fixture.mediaRequests, isEmpty);
    },
  );

  test('a queued download resumes after process-owner replacement', () async {
    policy.network = MediaNetwork.disconnected;
    await downloads.request(fixture.audio);
    expect(downloads.status(fixture.audio).phase, DownloadPhase.waiting);
    downloads.dispose();
    await downloads.idle;
    downloads = LocalDownloads(
      root: root,
      freeBytes: () async => capacity,
      policy: policy,
    );
    await downloads.bind(fixture.session(), fixture.books);
    expect(downloads.status(fixture.audio).phase, DownloadPhase.waiting);
    policy.network = MediaNetwork.wifi;
    await downloads.idle;
    expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
  });

  test(
    'disk space exhausted after the prefix never publishes a complete file',
    () async {
      fixture.holdItem = 'text';
      await downloads.request(fixture.text);
      await fixture.firstChunk.future;
      await waitForBytes(downloads, fixture.text, 3);
      capacity = 0;
      fixture.release();
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.failed);
      expect(await downloads.localFile(fixture.text.files.single), isNull);
      capacity = 1000000;
      fixture.holdItem = null;
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    },
  );

  test(
    'a server that ignores Range replaces rather than duplicates the prefix',
    () async {
      fixture.interruptOnce = true;
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.failed);
      fixture.ignoreRange = true;
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
      expect(
        await File.fromUri(
          (await downloads.localFile(fixture.text.files.single))!,
        ).readAsBytes(),
        [1, 2, 3, 4, 5, 6],
      );
    },
  );

  test('account and server identities keep completed files separate', () async {
    await downloads.request(fixture.text);
    await downloads.idle;
    expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    final alicePath = await downloads.localFile(fixture.text.files.single);
    await downloads.bind(fixture.session(user: 'bob'), fixture.books);
    expect(await downloads.localFile(fixture.text.files.single), isNull);
    fixture.serverId = 'different-server';
    await downloads.bind(fixture.session(), fixture.books);
    expect(await downloads.localFile(fixture.text.files.single), isNull);
    fixture.serverId = 'fixture-server';
    await downloads.bind(fixture.session(), fixture.books);
    expect(await downloads.localFile(fixture.text.files.single), alicePath);
  });

  test(
    'a request waiting on disk cannot queue a new account download',
    () async {
      policy.network = MediaNetwork.disconnected;
      final requesting = downloads.request(fixture.text);
      final switching = downloads.bind(
        fixture.session(user: 'bob'),
        fixture.books,
      );
      await Future.wait([requesting, switching]);
      expect(downloads.status(fixture.text).phase, DownloadPhase.none);
      policy.network = MediaNetwork.wifi;
      await downloads.idle;
      expect(fixture.mediaRequests, isEmpty);
    },
  );

  test(
    'the authenticated user must match the account that owns the job',
    () async {
      fixture.authenticatedUser = 'someone-else';
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.failed);
      expect(fixture.mediaRequests, isEmpty);
    },
  );

  test(
    'authorization uses the existing public server and current-user routes',
    () async {
      fixture.existingAuthorizationRoutesOnly = true;
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    },
  );

  test(
    'a source replaced during transfer is not published under the old revision',
    () async {
      final oldText = fixture.text;
      fixture.holdItem = 'text';
      await downloads.request(oldText);
      await fixture.firstChunk.future;
      await waitForBytes(downloads, oldText, 3);
      fixture.revision = 'source-v2';
      fixture.release();
      await downloads.idle;
      expect(downloads.status(oldText).phase, DownloadPhase.failed);
      expect(await downloads.localFile(oldText.files.single), isNull);
    },
  );

  test('a failed manifest write is reported without starting media', () async {
    policy.network = MediaNetwork.disconnected;
    await downloads.request(fixture.text);
    await downloads.cancel(fixture.text);
    final manifest = await root
        .list(recursive: true)
        .where((entity) => entity.path.endsWith('/record.json'))
        .first;
    await manifest.delete();
    await Directory(manifest.path).create();
    await downloads.request(fixture.text);
    policy.network = MediaNetwork.wifi;
    await downloads.idle;
    expect(downloads.status(fixture.text).phase, DownloadPhase.failed);
    expect(fixture.mediaRequests, isEmpty);
  });

  test(
    'retry immediately after cancel starts a new attempt after cancellation',
    () async {
      fixture.holdItem = 'text';
      await downloads.request(fixture.text);
      await fixture.firstChunk.future;
      await waitForBytes(downloads, fixture.text, 3);
      final cancelling = downloads.cancel(fixture.text);
      final retrying = downloads.request(fixture.text);
      fixture.holdItem = null;
      fixture.release();
      await Future.wait([cancelling, retrying]);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    },
  );

  test(
    'removing an edition removes its old revisions but keeps unrelated files',
    () async {
      await downloads.request(fixture.text);
      await downloads.idle;
      final oldFile = File.fromUri(
        (await downloads.localFile(fixture.text.files.single))!,
      );
      final unrelated = await File('${oldFile.parent.path}/user-note.txt')
          .writeAsString('keep');
      fixture.revision = 'source-v2';
      await downloads.bind(fixture.session(), fixture.books);
      await downloads.request(fixture.text);
      await downloads.idle;
      final newFile = File.fromUri(
        (await downloads.localFile(fixture.text.files.single))!,
      );
      expect(await oldFile.exists(), isTrue);
      expect(newFile.path, isNot(oldFile.path));
      await downloads.remove(fixture.text);
      expect(await oldFile.exists(), isFalse);
      expect(await newFile.exists(), isFalse);
      expect(await unrelated.readAsString(), 'keep');
    },
  );

  test(
    'a missing complete file contributes no bytes to a queued retry',
    () async {
      await downloads.request(fixture.text);
      await downloads.idle;
      final local = await downloads.localFile(fixture.text.files.single);
      expect(local, isNotNull);
      await File.fromUri(local!).delete();
      policy.network = MediaNetwork.unknown;
      await downloads.request(fixture.text);
      expect(downloads.status(fixture.text).phase, DownloadPhase.waiting);
      expect(downloads.status(fixture.text).bytes, 0);
    },
  );

  test(
    'player lookup waits for saved files before declaring them unavailable',
    () async {
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
      downloads.dispose();
      await downloads.idle;
      downloads = LocalDownloads(
        root: root,
        freeBytes: () async => capacity,
        policy: policy,
      );
      final restoring = downloads.bind(fixture.session(), fixture.books);
      final local = downloads.localFile(fixture.text.files.single);
      await restoring;
      expect(await local, isNotNull);
      expect(fixture.mediaRequests, ['text']);
    },
  );
}

class MediaFixture {
  MediaFixture(this.server);
  final HttpServer server;
  final requests = <HttpRequest>[];
  final mediaRequests = <String>[];
  final mediaTokens = <String?>[];
  final ranges = <String?>[];
  final ifRanges = <String?>[];
  List<int> payload = [1, 2, 3, 4, 5, 6];
  bool? allowDownload = true;
  bool bookWithoutMediaSources = false;
  List<Map<String, dynamic>>? textSources;
  bool audioWithoutMediaSources = false;
  bool requireModernAuthentication = false;
  bool itemDownloadable = true;
  bool administrator = false;
  String? denyItem;
  String? holdItem;
  bool interruptOnce = false;
  bool invalidRange = false;
  String etag = '"v1"';
  String revision = 'source-v1';
  String serverId = 'fixture-server';
  bool ignoreRange = false;
  String authenticatedUser = 'alice';
  bool existingAuthorizationRoutesOnly = false;
  final firstChunk = Completer<void>();
  final _released = Completer<void>();
  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}/jellyfin');
  JellyfinSession session({String user = 'alice'}) => JellyfinSession(
    scope: AccountScope(server: uri, serverId: serverId, userId: user),
    token: 'synthetic-token',
    username: user,
    canDownload: true,
  );
  Map<String, dynamic> dto(String id) => {
    'Id': id,
    'Name': id,
    'Type': id == 'text' ? 'Book' : 'AudioBook',
    'CanDownload': itemDownloadable,
    'Etag': 'catalog-v1',
    if (id == 'text' ? !bookWithoutMediaSources : !audioWithoutMediaSources)
      'MediaSources': id == 'text' && textSources != null
          ? textSources
          : [source(id)],
  };
  Map<String, dynamic> source(String id) => {
    'Id': id,
    'Type': 'Default',
    'IsRemote': false,
    'ETag': revision,
    'Size': 6,
    'Container': id.endsWith('text') ? 'epub' : 'm4b',
  };
  SourceFile file(String id) =>
      buildBooks([CatalogEntry.fromJson(dto(id), libraryId: 'books')])
          .single
          .editions
          .first
          .files
          .single;
  Edition get audio => Edition(
    id: 'recording',
    kind: EditionKind.audio,
    label: 'Recording',
    files: [file('audio1'), file('audio2')],
    memberIds: ['audio1:audio1', 'audio2:audio2'],
  );
  Edition get text => Edition(
    id: 'text:text',
    kind: EditionKind.text,
    label: 'EPUB',
    files: [file('text')],
    memberIds: ['text:text'],
  );
  List<Book> get books => [
    Book(
      id: 'work',
      title: 'Synthetic Work',
      author: 'Fixture Author',
      editions: [audio, text],
    ),
  ];
  static Future<MediaFixture> start() async {
    final fixture = MediaFixture(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.server.listen((request) async {
      try {
        await fixture._respond(request);
      } catch (_) {}
    });
    return fixture;
  }

  Future<void> _respond(HttpRequest request) async {
    requests.add(request);
    final parts = request.uri.pathSegments;
    final response = request.response;
    response.headers.contentType = ContentType.json;
    if (requireModernAuthentication &&
        parts.last != 'Public' &&
        request.headers
                .value('Authorization')
                ?.contains('Token="synthetic-token"') !=
            true) {
      response.statusCode = 401;
      await response.close();
      return;
    }
    if (parts.last == 'Info' || parts.last == 'Public') {
      if (existingAuthorizationRoutesOnly && parts.last != 'Public') {
        response.statusCode = 403;
        await response.close();
        return;
      }
      response.write(jsonEncode({'Id': serverId}));
    } else if (parts.length == 3 && parts[1] == 'Users') {
      if (existingAuthorizationRoutesOnly && parts.last != 'Me') {
        response.statusCode = 403;
        await response.close();
        return;
      }
      response.write(
        jsonEncode({
          'Id': parts.last == 'Me' ? authenticatedUser : parts.last,
          'Policy': {
            if (allowDownload != null)
              'EnableContentDownloading': allowDownload,
            'IsAdministrator': administrator,
          },
        }),
      );
    } else if (parts.last == 'Download') {
      final id = parts[parts.length - 2];
      mediaRequests.add(id);
      mediaTokens.add(request.headers.value('X-Emby-Token'));
      ranges.add(request.headers.value('Range'));
      ifRanges.add(request.headers.value('If-Range'));
      if (id == denyItem) {
        response.statusCode = 403;
        await response.close();
        return;
      }
      if (interruptOnce) {
        interruptOnce = false;
        final socket = await response.detachSocket(writeHeaders: false);
        socket.add(
          ascii.encode(
            'HTTP/1.1 200 OK\r\nContent-Length: 6\r\nETag: $etag\r\nConnection: close\r\n\r\n',
          ),
        );
        socket.add([1, 2, 3]);
        await socket.flush();
        socket.destroy();
        return;
      }
      final offset = ranges.last == null || ignoreRange ? 0 : 3;
      response.statusCode = offset == 0 ? 200 : 206;
      response.headers.set('ETag', etag);
      response.headers.set('Accept-Ranges', 'bytes');
      if (offset > 0) {
        response.headers.set(
          'Content-Range',
          invalidRange ? 'bytes 0-2/6' : 'bytes 3-5/6',
        );
      }
      response.contentLength = 6 - offset;
      response.bufferOutput = false;
      if (id == holdItem && offset == 0) {
        response.add([1, 2, 3]);
        await response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        if (!firstChunk.isCompleted) firstChunk.complete();
        await _released.future;
        response.add([4, 5, 6]);
      } else {
        response.add(payload.sublist(offset));
      }
    } else if (parts.length == 3 && parts[1] == 'Items') {
      response.write(jsonEncode(dto(parts.last)));
    } else {
      response.statusCode = 404;
    }
    await response.close();
  }

  Future<void> close() async {
    release();
    await server.close(force: true);
  }
}

Future<void> waitForBytes(
  Downloads downloads,
  Edition edition,
  int bytes,
) async {
  final ready = Completer<void>();
  void changed() {
    if (downloads.status(edition).bytes >= bytes && !ready.isCompleted) {
      ready.complete();
    }
  }

  downloads.addListener(changed);
  changed();
  try {
    await ready.future.timeout(const Duration(seconds: 5));
  } finally {
    downloads.removeListener(changed);
  }
}
