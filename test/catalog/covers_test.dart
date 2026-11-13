import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/catalog/covers_io.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory root;
  late List<Uri> requests;
  late Map<String, Uint8List?> server;
  var online = true;
  final session = JellyfinSession(
    scope: AccountScope(
      server: Uri.parse('https://books.example/jellyfin'),
      serverId: 'server',
      userId: 'alice',
    ),
    token: 'token',
    username: 'alice',
    canDownload: true,
  );
  late DiskCovers covers;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookfin-covers');
    requests = [];
    online = true;
    server = {
      'graft': Uint8List.fromList([1, 2, 3]),
    };
    covers = DiskCovers(
      root: root,
      fetch: (uri, headers) async {
        requests.add(uri);
        expect(headers['X-Emby-Token'], 'token');
        if (!online) throw const SocketException('offline');
        return server[uri.pathSegments[uri.pathSegments.length - 3]];
      },
    );
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'rejected credentials read kept covers without fetching missing ones',
    () async {
      final saved = const CoverRef('graft', 'v1');
      await covers.load(session, saved);
      final rejected = JellyfinSession.fromJson({
        ...session.toJson(),
        'needsSignIn': true,
      });
      final before = requests.length;
      expect(await covers.load(rejected, saved), [1, 2, 3]);
      expect(
        await covers.load(rejected, const CoverRef('missing', 'v1')),
        isNull,
      );
      expect(requests.length, before);
      server['missing'] = Uint8List.fromList([4]);
      expect(await covers.load(session, const CoverRef('missing', 'v1')), [4]);
    },
  );

  for (final blurred in [false, true]) {
    test(
      'replacement ${blurred ? 'blurred' : 'plain'} cover does not inherit a pending old rejection',
      () async {
        final old = JellyfinSession.fromJson(session.toJson());
        final replacement = JellyfinSession.fromJson(session.toJson());
        final pending = Completer<Uint8List?>();
        final started = Completer<void>();
        final bytes = img.encodePng(img.Image(width: 8, height: 12));
        var fetches = 0;
        covers = DiskCovers(
          root: root,
          fetch: (_, _) {
            if (++fetches == 1) {
              started.complete();
              return pending.future;
            }
            return Future.value(bytes);
          },
        );
        Future<Object?> load(JellyfinSession account) => blurred
            ? covers.blurred(account, const CoverRef('graft', 'v1'))
            : covers.load(account, const CoverRef('graft', 'v1'));
        final obsolete = load(old);
        await started.future;
        final current = load(replacement);
        pending.completeError(
          const CatalogFailure(CatalogFailureKind.unauthorized),
        );
        expect(await obsolete, isNull);
        final result = await current;
        expect(result, isNotNull);
        expect(fetches, 2);
        expect(old.needsSignIn, isTrue);
        expect(replacement.needsSignIn, isFalse);
        final restarted = DiskCovers(
          root: root,
          fetch: (_, _) async => throw const SocketException('offline'),
        );
        expect(
          await restarted.load(replacement, const CoverRef('graft', 'v1')),
          bytes,
        );
        if (blurred) {
          expect(
            img.decodeImage(await File.fromUri(result! as Uri).readAsBytes()),
            isNotNull,
          );
        }
      },
    );
  }

  test('a cover loaded once still shows offline', () async {
    expect(await covers.load(session, const CoverRef('graft', 'v1')), [
      1,
      2,
      3,
    ]);
    expect(
      requests.single.path,
      '/jellyfin/Items/graft/Images/Primary',
      reason: 'the server path prefix is kept',
    );
    expect(requests.single.queryParameters['tag'], 'v1');
    online = false;
    final restarted = DiskCovers(
      root: root,
      fetch: (_, _) async => throw const SocketException('offline'),
    );
    expect(await restarted.load(session, const CoverRef('graft', 'v1')), [
      1,
      2,
      3,
    ]);
  });

  test('a changed cover replaces the kept copy', () async {
    await covers.load(session, const CoverRef('graft', 'v1'));
    server['graft'] = Uint8List.fromList([9]);
    expect(await covers.load(session, const CoverRef('graft', 'v2')), [9]);
    online = false;
    expect(
      await covers.load(session, const CoverRef('graft', 'v1')),
      isNull,
      reason: 'the old version is removed',
    );
  });

  test('an item without a cover image shows no cover', () async {
    expect(await covers.load(session, const CoverRef('missing', 'v1')), isNull);
  });

  test('an unreachable server shows no cover and tries again later', () async {
    online = false;
    expect(await covers.load(session, const CoverRef('graft', 'v1')), isNull);
    online = true;
    expect(await covers.load(session, const CoverRef('graft', 'v1')), [
      1,
      2,
      3,
    ]);
  });

  test('one cover shown in many places is fetched once', () async {
    await Future.wait([
      for (var index = 0; index < 5; index++)
        covers.load(session, const CoverRef('graft', 'v1')),
    ]);
    expect(requests, hasLength(1));
  });

  test('clearing one account keeps every other account cover', () async {
    final bob = JellyfinSession(
      scope: AccountScope(
        server: session.scope.server,
        serverId: 'server',
        userId: 'bob',
      ),
      token: 'token',
      username: 'bob',
      canDownload: true,
    );
    await covers.load(session, const CoverRef('graft', 'v1'));
    await covers.load(bob, const CoverRef('graft', 'v1'));
    await covers.clear(session.scope);
    online = false;
    expect(await covers.load(bob, const CoverRef('graft', 'v1')), [1, 2, 3]);
    expect(await covers.load(session, const CoverRef('graft', 'v1')), isNull);
  });

  for (final blurred in [false, true]) {
    test(
      'a late ${blurred ? 'blurred' : 'plain'} cover cannot repopulate a cleared account',
      () async {
        final entered = Completer<void>();
        final release = Completer<Uint8List?>();
        covers = DiskCovers(
          root: root,
          fetch: (_, _) {
            if (!entered.isCompleted) entered.complete();
            return release.future;
          },
        );
        final loading = blurred
            ? covers.blurred(session, const CoverRef('graft', 'v1'))
            : covers.load(session, const CoverRef('graft', 'v1'));
        await entered.future;
        final clearing = covers.clear(session.scope);
        release.complete(img.encodePng(img.Image(width: 8, height: 12)));
        await clearing;
        await loading;
        final files = await root.exists()
            ? await root.list(recursive: true).where((f) => f is File).toList()
            : [];
        expect(files, isEmpty);
      },
    );
  }

  test('clearing removes every kept cover', () async {
    await covers.load(session, const CoverRef('graft', 'v1'));
    await covers.clear(session.scope);
    online = false;
    expect(await covers.load(session, const CoverRef('graft', 'v1')), isNull);
  });

  group('the blurred copy for the system media player', () {
    /// A cover [width] by 1.5 [width] pixels: red on the left half, blue on
    /// the right half.
    Uint8List halves(int width) {
      final cover = img.Image(width: width, height: width * 3 ~/ 2);
      for (final pixel in cover) {
        pixel
          ..r = pixel.x < width ~/ 2 ? 255 : 0
          ..g = 0
          ..b = pixel.x < width ~/ 2 ? 0 : 255;
      }
      return img.encodePng(cover);
    }

    /// The share of red in the red and blue of the blurred copy's pixel
    /// [across] its width on its middle row, from 0 to 1.
    double redShare(img.Image blurred, double across) {
      final pixel = blurred.getPixel(
        (blurred.width * across).floor(),
        blurred.height ~/ 2,
      );
      return pixel.r / (pixel.r + pixel.b);
    }

    setUp(() => server['graft'] = halves(480));

    test('is a file beside the kept cover that works offline', () async {
      final uri = await covers.blurred(session, const CoverRef('graft', 'v1'));
      expect(uri?.scheme, 'file');
      expect(
        uri!.toFilePath(),
        startsWith(root.path),
        reason: 'it is kept with the covers',
      );
      expect(img.decodeImage(await File.fromUri(uri).readAsBytes()), isNotNull);
      online = false;
      final restarted = DiskCovers(
        root: root,
        fetch: (_, _) async => throw const SocketException('offline'),
      );
      expect(
        await restarted.blurred(session, const CoverRef('graft', 'v1')),
        uri,
      );
      expect(requests, hasLength(1));
    });

    test('mixes the colors across the cover until no edge remains', () async {
      final uri = await covers.blurred(session, const CoverRef('graft', 'v1'));
      final blurred = img.decodeImage(await File.fromUri(uri!).readAsBytes())!;
      expect(redShare(blurred, 0.5), closeTo(0.5, 0.15));
      final row = [
        for (var x = 0; x < blurred.width; x++)
          blurred.getPixel(x, blurred.height ~/ 2).r.toInt(),
      ];
      for (var x = 1; x < row.length; x++) {
        expect(
          (row[x] - row[x - 1]).abs(),
          lessThan(40),
          reason: 'no sharp step remains at $x of ${row.length}',
        );
      }
    });

    test('keeps the colors of each side of the cover where they are', () async {
      final uri = await covers.blurred(session, const CoverRef('graft', 'v1'));
      final blurred = img.decodeImage(await File.fromUri(uri!).readAsBytes())!;
      expect(redShare(blurred, 0.2), greaterThan(0.9));
      expect(redShare(blurred, 0.8), lessThan(0.1));
    });

    test('is made once for each cover image', () async {
      final made = await Future.wait([
        for (var index = 0; index < 3; index++)
          covers.blurred(session, const CoverRef('graft', 'v1')),
      ]);
      expect(made.toSet(), hasLength(1));
      final kept = File.fromUri(made.first!);
      await kept.writeAsBytes([7]);
      expect(
        await covers.blurred(session, const CoverRef('graft', 'v1')),
        made.first,
      );
      expect(await kept.readAsBytes(), [7], reason: 'it is not made again');
    });

    test('of a changed cover replaces the older copy', () async {
      final old = await covers.blurred(session, const CoverRef('graft', 'v1'));
      server['graft'] = halves(240);
      final changed = await covers.blurred(
        session,
        const CoverRef('graft', 'v2'),
      );
      expect(changed, isNot(old));
      expect(await File.fromUri(changed!).exists(), isTrue);
      expect(await File.fromUri(old!).exists(), isFalse);
    });

    test('is made again after a crash cut its write short', () async {
      final uri = await covers.blurred(session, const CoverRef('graft', 'v1'));
      final kept = File.fromUri(uri!);
      // A kill mid-write leaves only the partial copy.
      await kept.delete();
      await File('${kept.path}.partial').writeAsBytes([1, 2]);
      final restarted = DiskCovers(root: root, fetch: (_, _) async => null);
      expect(
        await restarted.blurred(session, const CoverRef('graft', 'v1')),
        uri,
      );
      expect(img.decodeImage(await kept.readAsBytes()), isNotNull);
    });

    test('does not exist for an item without a readable cover image', () async {
      server['graft'] = Uint8List.fromList([1, 2, 3]);
      expect(
        await covers.blurred(session, const CoverRef('missing', 'v1')),
        isNull,
      );
      expect(
        await covers.blurred(session, const CoverRef('graft', 'v1')),
        isNull,
      );
      expect(
        await root
            .list(recursive: true)
            .where((entry) => entry.path.contains('graft@v1.'))
            .toList(),
        isEmpty,
        reason: 'no blurred copy and no partial copy is left',
      );
    });

    test('does not exist when the phone cannot store it', () async {
      final blocker = File('${root.path}/blocker');
      await blocker.writeAsString('not a directory');
      final unwritable = DiskCovers(
        root: Directory('${blocker.path}/covers'),
        fetch: (_, _) async => halves(480),
      );
      expect(
        await unwritable.blurred(session, const CoverRef('graft', 'v1')),
        isNull,
      );
    });
  });
}
