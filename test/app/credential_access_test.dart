import 'dart:async';
import 'dart:io';

import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:bookfin/playback/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bookfin/app/account_binding.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/controller_test.dart';
import '../downloads/transfer_test.dart' show MediaFixture;
import '../playback/playback_test.dart' show TestEngine;
import '../reader/publication_test.dart' show epub;
import '../reader/session_test.dart' show visible;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  for (final replacement in ['same', 'different', 'sign out']) {
    test(
      'local playback and reading survive 401 before $replacement account transition',
      () async {
        SharedPreferences.setMockInitialValues({});
        final fixture = await MediaFixture.start();
        fixture.payload = epub();
        final root = await Directory.systemTemp.createTemp('bookfin-401-');
        final credentials = MemoryCredentials();
        final store = MemoryCatalogStore();
        final client = FixtureClient(fixture.uri)
          ..pendingSignIn = (Completer<JellyfinSession>()
            ..complete(fixture.session()))
          ..entries = [
            for (final id in ['audio1', 'text'])
              CatalogEntry.fromJson(fixture.dto(id), libraryId: 'books'),
          ];
        final catalog = CatalogController(
          credentials: credentials,
          store: store,
          clientFactory: (_, _) => client,
        );
        await catalog.connect(fixture.uri.toString(), 'alice', 'password');
        final audio = catalog.books.singleWhere(
          (book) => book.editions.single.kind == EditionKind.audio,
        );
        final text = catalog.books.singleWhere(
          (book) => book.editions.single.kind == EditionKind.text,
        );
        final policy = MediaPolicy()..network = MediaNetwork.wifi;
        final files = LocalDownloads(
          root: root,
          freeBytes: () async => 10000000,
          policy: policy,
        );
        final records = LocalResumeStore();
        final engine = TestEngine();
        final playback = Playback(
          downloads: files,
          engine: engine,
          store: records,
        );
        final reader = ReaderSession(
          downloads: files,
          store: records.reading,
          load: (file) async =>
              Publication.admit(await File.fromUri(file.uri).readAsBytes()),
        );
        final binding = AccountBinding(
          catalog: catalog,
          downloads: files,
          playback: playback,
          reader: reader,
        );
        addTearDown(() async {
          binding.dispose();
          await playback.close();
          reader.dispose();
          files.dispose();
          await files.idle;
          policy.dispose();
          catalog.dispose();
          await fixture.close();
          await root.delete(recursive: true);
        });
        await pumpEventQueue();
        await files.request(audio.editions.single);
        await files.request(text.editions.single);
        await files.idle;
        await playback.open(audio, audio.editions.single);
        await reader.open(text, text.editions.single);
        reader.acceptVisible(reader.token, visible);
        final publication = reader.publication;
        final readerToken = reader.token;
        client.failure = const CatalogFailure(CatalogFailureKind.unauthorized);
        await catalog.refresh();
        await pumpEventQueue();
        expect(playback.playing, isTrue);
        expect(reader.publication, same(publication));
        expect(reader.token, readerToken);
        engine.emit(0, 15000, playing: true);
        await reader.addBookmark(title: 'After sign-in expired');
        await Future.wait([playback.flush(), reader.flush()]);
        final key = catalog.session!.scope.key;
        expect(await records.pendingUploads(key), isNotEmpty);
        expect(reader.bookmarks.single.title, 'After sign-in expired');
        if (replacement == 'sign out') {
          await catalog.signOut();
        } else {
          client.failure = null;
          final user = replacement == 'same' ? 'alice' : 'bob';
          client.pendingSignIn = Completer()
            ..complete(
              JellyfinSession(
                scope: fixture.session(user: user).scope,
                token: 'replacement-token',
                username: user,
                canDownload: true,
              ),
            );
          await catalog.connect(fixture.uri.toString(), user, 'password');
        }
        await pumpEventQueue();
        if (replacement == 'same') {
          expect(playback.playing, isTrue);
          expect(playback.position!.milliseconds, 15000);
          expect(reader.publication, same(publication));
          expect(reader.token, readerToken);
          expect(reader.bookmarks.single.title, 'After sign-in expired');
          expect(catalog.verified, isTrue);
        } else {
          expect(playback.playing, isFalse);
          expect(reader.publication, isNull);
          expect(reader.bookmarks, isEmpty);
        }
        // Old account data remains readable after either transition.
        final reopened = ReaderSession(
          downloads: files,
          store: LocalResumeStore().reading,
          load: (file) async =>
              Publication.admit(await File.fromUri(file.uri).readAsBytes()),
        );
        await files.bind(fixture.session(), [text]);
        await reopened.bind(fixture.session(), [text]);
        await reopened.open(text, text.editions.single);
        expect(reopened.bookmarks.single.title, 'After sign-in expired');
        expect(reopened.initialLocation?.cfi, visible.cfi);
        reopened.dispose();
        catalog.checkInvariants();
        binding.checkInvariants();
        playback.checkInvariants();
        reader.checkInvariants();
      },
    );
  }
}
