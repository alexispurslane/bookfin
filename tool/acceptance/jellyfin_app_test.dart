import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_support.dart';

const enabled = bool.fromEnvironment('BOOKFIN_APP_ACCEPTANCE');
const firstTrack = 'public/Work/Recording A/z-first.m4b';
const secondTrack = 'public/Work/Recording A/a-second.m4b';
const thirdTrack = 'public/Work/Recording A/m-third.m4b';
const otherRecording = 'public/Work/Recording B/other-narrator.m4b';
const ebook = 'public/Work/Text Edition/Synthetic Work.epub';
const hiddenTrack = 'private/Hidden/secret-synthetic.m4b';

void main() {
  group('production app against disposable Jellyfin', skip: !enabled, () {
    late Map<String, dynamic> manifest;
    late Map<String, dynamic> accounts;
    late Map<String, dynamic> passwords;
    late Uri origin;
    late Directory directory;
    late DiskCredentials credentials;
    late DiskCatalog store;
    late CatalogController catalog;
    late MediaPolicy policy;
    late LocalDownloads downloads;
    late List<HttpObservation> observations;
    final results = <String, dynamic>{};
    late HttpOverrides? previousOverrides;
    String library(String name) =>
        manifest['libraries']['Synthetic $name'] as String;
    String item(String path) => manifest['sources'][path]['itemId'] as String;
    String getToken(String name) => accounts[name]['token'] as String;

    JellyfinClient client() =>
        JellyfinClient(origin, deviceId: 'boo-2cgp-live');
    List<Edition> editions() =>
        catalog.books.expand((book) => book.editions).toList();
    Edition edition(String path) => editions().singleWhere(
      (edition) => edition.files.any((source) => source.itemId == item(path)),
    );
    Book book(String path) => catalog.books.singleWhere(
      (book) => book.editions.any(
        (edition) => edition.files.any((source) => source.itemId == item(path)),
      ),
    );
    Future<void> connect(String name, {Set<String>? selected}) async {
      await catalog.connect(
        origin.toString(),
        'research-$name',
        passwords['research-$name'] as String,
      );
      expect(catalog.message, isNull);
      expect(catalog.session?.scope.userId, accounts[name]['id']);
      await catalog.refresh(selected: selected ?? {library('public')});
      expect(catalog.message, isNull);
      expect(catalog.verified, isTrue);
      catalog.checkInvariants();
      await downloads.bind(catalog.session, catalog.books);
    }

    Future<Map<String, dynamic>> accountDetails(String name) => rawJson(
      origin,
      'GET',
      '/Users/${accounts[name]['id']}',
      token: getToken('admin'),
    );
    Future<void> setPolicy(String name, Map<String, dynamic> value) => rawJson(
      origin,
      'POST',
      '/Users/${accounts[name]['id']}/Policy',
      token: getToken('admin'),
      body: value,
      expectedStatus: 204,
    );
    Future<void> downloadExactly(Edition target) async {
      await downloads.request(target);
      await downloads.idle;
      expect(
        downloads.status(target).phase,
        DownloadPhase.downloaded,
        reason: downloads.status(target).message,
      );
      for (final source in target.files) {
        final expected = (manifest['sources'] as Map).values
            .cast<Map>()
            .singleWhere((value) => value['itemId'] == source.itemId);
        final local = await downloads.localFile(source);
        expect(local, isNotNull);
        final bytes = await File.fromUri(local!).readAsBytes();
        expect(bytes, await File(expected['path'] as String).readAsBytes());
        expect(bytes.length, expected['length']);
        expect(sha256.convert(bytes).toString(), expected['sha256']);
      }
      downloads.checkInvariants();
    }

    void record(String name, Map<String, dynamic> facts) {
      expect(
        observations.where(
          (value) => value.uri.queryParameters.keys.any(
            (key) =>
                key.toLowerCase().contains('token') ||
                key.toLowerCase().contains('password'),
          ),
        ),
        isEmpty,
      );
      expect(
        observations.where((value) => value.uri.path.endsWith('/File')),
        isEmpty,
        reason:
            'No production path may bypass Download authorization with File',
      );
      results[name] = {
        'passed': true,
        ...facts,
        'http': observations.map((value) => value.toJson()).toList(),
      };
    }

    setUpAll(() async {
      manifest = privateJson('app-acceptance.json');
      accounts = privateJson('accounts.json');
      passwords = privateJson('passwords.json');
      origin = Uri.parse(manifest['origin'] as String);
      expect(origin.toString(), 'http://127.0.0.1:7364');
      final marker = privateJson('fixture.json');
      expect(marker['serverId'], manifest['serverId']);
      final public = await rawJson(origin, 'GET', '/System/Info/Public');
      expect(public['Id'], manifest['serverId']);
      expect(public['Version'], '12.4.0');
      for (final name in ['alice', 'bob']) {
        final details = await accountDetails(name);
        expect(details['Policy']['IsAdministrator'], isFalse);
        expect(details['Policy']['EnableContentDownloading'], isTrue);
      }
      for (final path in ['accounts.json', 'passwords.json']) {
        expect((await File('${runtime.path}/$path').stat()).mode & 0x3f, 0);
      }
    });

    setUp(() async {
      observations = [];
      previousOverrides = HttpOverrides.current;
      HttpOverrides.global = ObservationOverrides(observations);
      final parent = await Directory('${runtime.path}/app-tests')
          .create(recursive: true);
      directory = await parent.createTemp('run-');
      credentials = DiskCredentials(directory);
      store = DiskCatalog(directory);
      catalog = CatalogController(credentials: credentials, store: store);
      policy = MediaPolicy()..network = MediaNetwork.wifi;
      downloads = LocalDownloads(
        root: Directory('${directory.path}/downloads'),
        freeBytes: () async => 1024 * 1024 * 1024,
        policy: policy,
      );
    });

    tearDown(() async {
      catalog.dispose();
      downloads.dispose();
      await downloads.idle;
      policy.dispose();
      HttpOverrides.global = previousOverrides;
      await directory.delete(recursive: true);
    });

    tearDownAll(() async {
      await writePrivate(
        File('${runtime.path}/app-results.json'),
        const JsonEncoder.withIndent('  ').convert({
          'baseline': 'ae6be0e84539515b5c77cbb419b2f0a67c923cfd',
          'executedAtUtc': DateTime.now().toUtc().toIso8601String(),
          'serverVersion': manifest['version'],
          'serverId': manifest['serverId'],
          'results': results,
        }),
      );
    });

    test('ordinary accounts see only authorized book libraries and selected sources', () async {
      await connect('alice', selected: {library('public'), library('private')});
      expect(catalog.libraries.map((value) => value.id).toSet(), {
        library('public'),
        library('private'),
      });
      expect(
        editions()
            .expand((value) => value.files)
            .map((value) => value.itemId)
            .toSet(),
        {
          item(firstTrack),
          item(secondTrack),
          item(thirdTrack),
          item(otherRecording),
          item(ebook),
          item(hiddenTrack),
        },
      );
      await catalog.refresh(selected: {library('private')});
      expect(catalog.books, hasLength(1));
      expect(edition(hiddenTrack).files.single.itemId, item(hiddenTrack));
      await connect('bob');
      expect(catalog.libraries.map((value) => value.id), [library('public')]);
      expect(catalog.books, hasLength(5));
      final views = await rawJson(
        origin,
        'GET',
        '/UserViews?userId=${accounts['bob']['id']}',
        token: catalog.session!.token,
      );
      expect(
        (views['Items'] as List).any(
          (value) => value['Id'] == library('music'),
        ),
        isTrue,
      );
      final api = client();
      try {
        for (final selection in [
          {library('music')},
          {library('private')},
        ]) {
          await expectLater(
            api.catalog(catalog.session!, selection),
            throwsA(
              isA<CatalogFailure>().having(
                (failure) => failure.kind,
                'kind',
                CatalogFailureKind.invalidSelection,
              ),
            ),
          );
        }
      } finally {
        api.close();
      }
      expect(
        observations.where(
          (value) =>
              value.uri.path == '/Items' &&
              value.uri.queryParameters['parentId'] == library('music'),
        ),
        isEmpty,
      );
      record('account-filtering', {
        'aliceBookSources': 6,
        'bobBookSources': 5,
        'nonBookLibraryVisibleToServerButExcludedByApp': true,
      });
    });

    test('matching titles and folders need explicit book and recording corrections', () async {
      await connect('alice');
      expect(catalog.books.map((value) => value.title).toSet(), {
        'Synthetic Work',
      });
      expect(catalog.books, hasLength(5));
      expect(editions().every((value) => value.files.length == 1), isTrue);
      final target = book(firstTrack).id;
      for (final path in [thirdTrack, secondTrack, otherRecording, ebook]) {
        await catalog.linkBooks(book(path).id, target);
      }
      expect(catalog.books.single.editions, hasLength(5));
      final memberIds = [
        edition(thirdTrack).id,
        edition(secondTrack).id,
        edition(firstTrack).id,
      ];
      await catalog.combineAudio(target, memberIds);
      var recording = edition(firstTrack);
      expect(recording.files.map((value) => value.itemId), [
        item(firstTrack),
        item(secondTrack),
        item(thirdTrack),
      ]);
      expect(catalog.books.single.editions, hasLength(3));
      expect(edition(otherRecording).files, hasLength(1));
      expect(edition(ebook).kind, EditionKind.text);
      expect(
        () => catalog.combineAudio(target, [recording.id, edition(ebook).id]),
        throwsArgumentError,
      );
      expect(recording.files.first.chapters.map((value) => value.startMs), [
        0,
        90000,
      ]);
      final reversed = recording.files.reversed
          .map((value) => value.key)
          .toList();
      await catalog.orderFiles(recording.id, reversed);
      await catalog.refresh();
      recording = edition(firstTrack);
      expect(recording.files.map((value) => value.itemId), [
        item(thirdTrack),
        item(secondTrack),
        item(firstTrack),
      ]);
      catalog.dispose();
      catalog = CatalogController(
        credentials: DiskCredentials(directory),
        store: DiskCatalog(directory),
      );
      final beforeRestore = observations.length;
      await catalog.restore();
      expect(observations.length, beforeRestore);
      expect(catalog.verified, isFalse);
      expect(edition(firstTrack).files.map((value) => value.itemId), [
        item(thirdTrack),
        item(secondTrack),
        item(firstTrack),
      ]);
      await connect('bob');
      expect(catalog.books, hasLength(5));
      await connect('alice');
      expect(catalog.books.single.editions, hasLength(3));
      catalog.checkInvariants();
      record('explicit-corrections', {
        'initialSeparateBooks': 5,
        'confirmedBookEditions': 3,
        'recordingFiles': 3,
        'credentialStore':
            'test-only private disk, not platform secure storage',
      });
    });

    test('completed multi-file audio and ebook bytes survive owner restart without crossing accounts', () async {
      await connect('alice');
      final target = book(firstTrack).id;
      for (final path in [thirdTrack, secondTrack]) {
        await catalog.linkBooks(book(path).id, target);
      }
      await catalog.combineAudio(target, [
        edition(thirdTrack).id,
        edition(firstTrack).id,
        edition(secondTrack).id,
      ]);
      await downloads.bind(catalog.session, catalog.books);
      final audio = edition(firstTrack);
      final text = edition(ebook);
      await downloadExactly(audio);
      await downloadExactly(text);
      final alicePaths = <Uri>[];
      for (final source in [...audio.files, ...text.files]) {
        alicePaths.add((await downloads.localFile(source))!);
      }
      final beforeRestart = observations.length;
      downloads.dispose();
      await downloads.idle;
      downloads = LocalDownloads(
        root: Directory('${directory.path}/downloads'),
        freeBytes: () async => 1024 * 1024 * 1024,
        policy: policy,
      );
      await downloads.bind(catalog.session, catalog.books);
      expect(downloads.status(audio).completeFiles, 3);
      expect(downloads.status(text).phase, DownloadPhase.downloaded);
      expect(observations.length, beforeRestart);
      await connect('bob');
      expect(downloads.status(edition(ebook)).phase, DownloadPhase.none);
      expect(await downloads.localFile(edition(ebook).files.single), isNull);
      await downloadExactly(edition(ebook));
      expect(
        await downloads.localFile(edition(ebook).files.single),
        isNot(alicePaths.last),
      );
      await connect('alice');
      expect(downloads.status(audio).completeFiles, 3);
      expect(await downloads.localFile(text.files.single), alicePaths.last);
      await catalog.signOut();
      await downloads.bind(null, []);
      expect(await downloads.localFile(text.files.single), isNull);
      expect(await credentials.read(), isNull);
      downloads.checkInvariants();
      record('whole-edition-bytes-and-account-storage', {
        'audioFiles': 3,
        'ebookFiles': 1,
        'allBytesAndSha256EqualSyntheticSources': true,
        'restartRevalidationWithoutHttp': true,
        'bobHasSeparatePathForSameSource': true,
      });
    });

    test('an interrupted real transfer restarts safely when Jellyfin omits a strong validator', () async {
      await connect('alice');
      final target = edition(firstTrack);
      var interrupted = false;
      void interrupt() {
        final status = downloads.status(target);
        if (!interrupted &&
            status.bytes > 0 &&
            status.bytes < target.files.single.sizeBytes!) {
          interrupted = true;
          policy.network = MediaNetwork.disconnected;
        }
      }

      downloads.addListener(interrupt);
      await downloads.request(target);
      await downloads.idle;
      downloads.removeListener(interrupt);
      expect(interrupted, isTrue);
      final prefix = downloads.status(target).bytes;
      expect(prefix, greaterThan(0));
      expect(prefix, lessThan(target.files.single.sizeBytes!));
      downloads.dispose();
      await downloads.idle;
      downloads = LocalDownloads(
        root: Directory('${directory.path}/downloads'),
        freeBytes: () async => 1024 * 1024 * 1024,
        policy: policy,
      );
      await downloads.bind(catalog.session, catalog.books);
      expect(downloads.status(target).bytes, prefix);
      policy.network = MediaNetwork.wifi;
      await downloads.idle;
      await downloadExactly(target);
      final transfers = observations
          .where(
            (value) => value.uri.path == '/Items/${item(firstTrack)}/Download',
          )
          .toList();
      expect(transfers, hasLength(2));
      expect(transfers.map((value) => value.etag), everyElement(isNull));
      expect(
        transfers.map((value) => value.lastModified),
        everyElement(isNotEmpty),
      );
      expect(transfers.map((value) => value.range), everyElement(isNull));
      expect(transfers.map((value) => value.status), everyElement(200));
      record('interruption-and-safe-restart', {
        'savedPrefixBytes': prefix,
        'retryHttpStatus': 200,
        'strongHttpEtagAbsent': true,
        'rangeResumeProven': false,
        'exactCompletedBytes': true,
      });
    });

    test('live disabled download permission rejects stale authorization and recovers without File', () async {
      await connect('alice');
      final target = edition(ebook);
      final original = Map<String, dynamic>.from(
        (await accountDetails('alice'))['Policy'],
      );
      try {
        await setPolicy('alice', {
          ...original,
          'EnableContentDownloading': false,
        });
        expect(catalog.session!.canDownload, isTrue);
        await downloads.request(target);
        await downloads.idle;
        expect(downloads.status(target).phase, DownloadPhase.failed);
        expect(await downloads.localFile(target.files.single), isNull);
        expect(
          observations.where((value) => value.uri.path.endsWith('/Download')),
          isEmpty,
        );
        await rawJson(
          origin,
          'GET',
          '/Items/${item(ebook)}/Download',
          token: catalog.session!.token,
          expectedStatus: 403,
        );
        await catalog.refresh();
        expect(catalog.session!.canDownload, isFalse);
        await setPolicy('alice', original);
        await catalog.refresh();
        expect(catalog.session!.canDownload, isTrue);
        await downloads.bind(catalog.session, catalog.books);
        await downloadExactly(edition(ebook));
        record('live-download-permission-recovery', {
          'staleClientPermissionRejected': true,
          'rawDownloadWhileDisabled': 403,
          'enabledAgainDownloadsExactBytes': true,
        });
      } finally {
        await setPolicy('alice', original);
      }
    });

    test('inaccessible and nonexistent sources never publish bytes or fall back to File', () async {
      await connect('alice', selected: {library('private')});
      final hidden = edition(hiddenTrack);
      final aliceBooks = catalog.books;
      await connect('bob');
      await downloads.bind(catalog.session, aliceBooks);
      await downloads.request(hidden);
      await downloads.idle;
      expect(downloads.status(hidden).phase, DownloadPhase.failed);
      expect(await downloads.localFile(hidden.files.single), isNull);
      expect(
        observations.any(
          (value) =>
              value.uri.path == '/Items/${item(hiddenTrack)}' &&
              value.status == 404,
        ),
        isTrue,
      );
      for (final id in [
        item(hiddenTrack),
        '00000000000000000000000000000001',
      ]) {
        await rawJson(
          origin,
          'GET',
          '/Items/$id/Download',
          token: catalog.session!.token,
          expectedStatus: 404,
        );
      }
      await rawJson(
        origin,
        'GET',
        '/Items?userId=${accounts['alice']['id']}',
        token: catalog.session!.token,
        expectedStatus: 403,
      );
      await rawJson(
        origin,
        'GET',
        '/Items/${item(ebook)}/Download',
        expectedStatus: 401,
      );
      record('inaccessible-sources', {
        'appRejectedHiddenItemResponse': 404,
        'hiddenAndMissingRawDownload': 404,
        'impersonation': 403,
        'unauthenticatedDownload': 401,
      });
    });

    test('library revocation hides cached content across restoration and permits explicit recovery', () async {
      await connect('alice', selected: {library('private')});
      final original = Map<String, dynamic>.from(
        (await accountDetails('alice'))['Policy'],
      );
      try {
        await setPolicy('alice', {
          ...original,
          'EnabledFolders': [library('public'), library('music')],
        });
        await catalog.refresh();
        expect(catalog.accessBlocked, isTrue);
        expect(catalog.books, isEmpty);
        catalog.dispose();
        catalog = CatalogController(
          credentials: DiskCredentials(directory),
          store: DiskCatalog(directory),
        );
        await catalog.restore();
        expect(catalog.accessBlocked, isTrue);
        expect(catalog.books, isEmpty);
        await setPolicy('alice', original);
        await catalog.refresh(selected: {library('private')});
        expect(catalog.accessBlocked, isFalse);
        expect(catalog.books, hasLength(1));
        expect(edition(hiddenTrack).files.single.itemId, item(hiddenTrack));
        catalog.checkInvariants();
        record('library-revocation-and-recovery', {
          'blockedCacheRemainsHiddenOnRestore': true,
          'restoredPermissionAndExplicitSelectionRecover': true,
        });
      } finally {
        await setPolicy('alice', original);
      }
    });

    test('fresh server and user identities reject a mismatched saved download account', () async {
      await connect('alice');
      final session = catalog.session!;
      final target = edition(firstTrack);
      for (final scope in [
        AccountScope(
          server: origin,
          serverId: 'synthetic-wrong-installation',
          userId: session.scope.userId,
        ),
        AccountScope(
          server: origin,
          serverId: session.scope.serverId,
          userId: accounts['bob']['id'] as String,
        ),
      ]) {
        await downloads.bind(
          JellyfinSession(
            scope: scope,
            token: session.token,
            username: session.username,
            canDownload: true,
          ),
          catalog.books,
        );
        await downloads.request(target);
        await downloads.idle;
        expect(downloads.status(target).phase, DownloadPhase.failed);
        expect(await downloads.localFile(target.files.single), isNull);
      }
      expect(
        observations.where((value) => value.uri.path.endsWith('/Download')),
        isEmpty,
      );
      expect(
        observations.where(
          (value) => value.uri.path == '/Users/Me' && value.status == 200,
        ),
        hasLength(3),
      );
      record('download-account-identity', {
        'mismatchedSavedServerAndUserRejectedAgainstRealResponses': true,
        'mediaRequests': 0,
      });
    });

    test('a changed server source revision rejects stale acquisition and hides the previous local revision', () async {
      await connect('alice');
      final target = edition(otherRecording);
      final oldSource = target.files.single;
      await downloadExactly(target);
      final oldLocal = await downloads.localFile(oldSource);
      final oldBooks = catalog.books;
      final originalDetails = await rawJson(
        origin,
        'GET',
        '/Items/${item(otherRecording)}',
        token: getToken('admin'),
      );
      final expected =
          manifest['sources'][otherRecording] as Map<String, dynamic>;
      final sourceFile = File(expected['path'] as String);
      final originalBytes = await sourceFile.readAsBytes();
      final replacementBytes = [
        ...originalBytes,
        ...utf8.encode('Bookfin synthetic replacement only'),
      ];
      final originalLength = expected['length'];
      final originalHash = expected['sha256'];
      Future<void> refreshSource(int length) async {
        await rawJson(
          origin,
          'POST',
          '/Items/${item(otherRecording)}/Refresh?metadataRefreshMode=FullRefresh&imageRefreshMode=None&replaceAllMetadata=false&replaceAllImages=false',
          token: getToken('admin'),
          expectedStatus: 204,
        );
        for (var attempt = 0; attempt < 100; attempt++) {
          await catalog.refresh();
          expect(catalog.message, isNull);
          if (edition(otherRecording).files.single.sizeBytes == length) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        fail('The disposable source did not refresh to $length bytes');
      }

      final stale = LocalDownloads(
        root: Directory('${directory.path}/stale-downloads'),
        freeBytes: () async => 1024 * 1024 * 1024,
        policy: policy,
      );
      try {
        await sourceFile.writeAsBytes(replacementBytes, flush: true);
        await refreshSource(replacementBytes.length);
        expected['length'] = replacementBytes.length;
        expected['sha256'] = sha256.convert(replacementBytes).toString();
        await stale.bind(catalog.session, oldBooks);
        final downloadsBefore = observations
            .where((value) => value.uri.path.endsWith('/Download'))
            .length;
        await stale.request(target);
        await stale.idle;
        expect(stale.status(target).phase, DownloadPhase.failed);
        expect(await stale.localFile(oldSource), isNull);
        expect(
          observations.where((value) => value.uri.path.endsWith('/Download')),
          hasLength(downloadsBefore),
        );
        await catalog.refresh();
        expect(catalog.message, isNull);
        final replacement = edition(otherRecording);
        expect(replacement.files.single.key, oldSource.key);
        expect(replacement.files.single.revision, isNot(oldSource.revision));
        await downloads.bind(catalog.session, catalog.books);
        expect(await downloads.localFile(replacement.files.single), isNull);
        await downloadExactly(replacement);
        expect(
          await downloads.localFile(replacement.files.single),
          isNot(oldLocal),
        );
        expect(await File.fromUri(oldLocal!).exists(), isTrue);
        await downloads.remove(replacement);
        expect(await File.fromUri(oldLocal).exists(), isFalse);
        expect(await downloads.localFile(replacement.files.single), isNull);
      } finally {
        stale.dispose();
        await stale.idle;
        await sourceFile.writeAsBytes(originalBytes, flush: true);
        expected['length'] = originalLength;
        expected['sha256'] = originalHash;
        await refreshSource(originalBytes.length);
        await rawJson(
          origin,
          'POST',
          '/Items/${item(otherRecording)}',
          token: getToken('admin'),
          body: originalDetails,
          expectedStatus: 204,
        );
        await catalog.refresh();
        expect(book(otherRecording).title, originalDetails['Name']);
      }
      record('download-source-identity', {
        'realSourceByteReplacementChangesRevision': true,
        'staleSourceRejectedBeforeMedia': true,
        'newRevisionHasSeparateStorage': true,
        'removeAlsoDeletesOldOwnedRevision': true,
      });
    });
  });
}
